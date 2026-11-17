import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'open_xr_bounds.dart';
import 'open_xr_controller_state.dart';

/// Grip-to-grab for one scene node, run on the native XR frame clock.
///
/// A grip pressed while the controller points at (or touches) the node
/// holds it: the node follows that controller rigidly, and the same hand's
/// stick pushes it along the aim ray (up) or pulls it closer (down). While
/// one hand holds the node, the other grip joins from anywhere; the pair
/// then scales the node by the change in distance between the controllers,
/// about their midpoint, which the node also follows.
///
/// The node is looked up by [nodeName] each frame, so content that remounts
/// keeps working. Grips that hold a floating panel arrive as 0 from the host
/// and never reach this class.
class OpenXrGrab {
  OpenXrGrab({
    required this.nodeName,
    this.minScale = 0.02,
    this.maxScale = 4,
    this.reach = 0.12,
    this.onGrab,
    this.onRelease,
    this.onPrimaryButton,
  });

  /// Name of the node to grab, searched below the scene root.
  final String nodeName;

  /// World-space scale limits for the two-hand gesture.
  final double minScale;
  final double maxScale;

  /// Metres around the node's bounds that still count as touching it.
  final double reach;

  /// Called when the first hand takes the node, so its owner can pause its
  /// own motion (physics) while held.
  final void Function()? onGrab;

  /// Called when the last hand lets go, with the node's world velocity over
  /// the final moments of the hold, so a release can become a throw.
  final void Function(vm.Vector3 velocity)? onRelease;

  /// Called on each primary button (A/X) press while the node exists.
  final void Function(int hand)? onPrimaryButton;

  // Grip hysteresis, matching the native panel grip.
  static const _gripPress = 0.65;
  static const _gripRelease = 0.35;

  // Stick push/pull: speed at full deflection is this many metres per second
  // per metre of distance, so far objects move faster, but never slower than
  // the minimum. The node stays at least [_closest] metres from the hand.
  static const _stickDeadZone = 0.15;
  static const _pushRate = 1.5;
  static const _pushMinimumSpeed = 0.5;
  static const _closest = 0.1;

  // Window of held positions the release velocity is measured over: short
  // enough to follow the hand's final flick.
  static const _throwWindow = 0.08;

  final _clock = Stopwatch()..start();
  double _lastUpdate = 0;
  final _gripDown = [false, false];
  final _primaryDown = [false, false];
  final _holding = [false, false];
  Node? _target;
  final _trail = <(double, vm.Vector3)>[];

  // Captured whenever the set of holding hands changes.
  vm.Matrix4? _targetFromHand;
  vm.Matrix4? _start;
  vm.Vector3? _startMidpoint;
  double _startDistance = 0;

  /// Whether a hand currently holds the node.
  bool get holding => _holding[0] || _holding[1];

  void update(
    Scene scene,
    OpenXrControllerState controllers,
    vm.Matrix4? worldFromReference,
  ) {
    final now = _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
    final dt = (now - _lastUpdate).clamp(0.0, 0.1);
    _lastUpdate = now;
    final node = scene.root.getChildByName(nodeName);
    if (node != _target) {
      _target = node;
      _letGo();
    }
    if (node == null) return;
    final wasHolding = holding;

    final reference = worldFromReference ?? vm.Matrix4.identity();
    final hands = <vm.Matrix4?>[null, null];
    var changed = false;
    for (var hand = 0; hand < 2; hand++) {
      final aim = hand < controllers.aims.length
          ? controllers.aims[hand]
          : null;
      final tracked = aim != null && aim.tracked;
      final down =
          tracked && aim.grip > (_gripDown[hand] ? _gripRelease : _gripPress);
      final pressed = down && !_gripDown[hand];
      _gripDown[hand] = down;
      final primary = tracked && aim.primaryButton;
      if (primary && !_primaryDown[hand]) onPrimaryButton?.call(hand);
      _primaryDown[hand] = primary;
      if (!tracked) {
        changed |= _holding[hand];
        _holding[hand] = false;
        continue;
      }
      // Matrix4.compose matches OpenXR's quaternion convention; -Z aims.
      final pose =
          reference *
          vm.Matrix4.compose(aim.position, aim.orientation, vm.Vector3.all(1));
      hands[hand] = pose;
      if (_holding[hand] && !down) {
        _holding[hand] = false;
        changed = true;
      } else if (pressed &&
          !_holding[hand] &&
          (_holding[1 - hand] || _hits(node, pose))) {
        _holding[hand] = true;
        changed = true;
      }
    }

    if (changed) _capture(node, hands);
    if (_holding[0] && _holding[1]) {
      _applyPinch(node, hands[0]!, hands[1]!);
    } else if (_targetFromHand != null) {
      final hand = _holding[0] ? 0 : 1;
      final stick = hand == 0
          ? controllers.leftThumbstick.y
          : controllers.rightThumbstick.y;
      if (stick.abs() > _stickDeadZone) _push(stick * dt);
      node.globalTransform = hands[hand]! * _targetFromHand!;
    }
    _trackRelease(node, now, wasHolding);
  }

  void _applyPinch(Node node, vm.Matrix4 left, vm.Matrix4 right) {
    final a = left.getTranslation();
    final b = right.getTranslation();
    final startScale = _start!.getMaxScaleOnAxis();
    final factor = (a.distanceTo(b) / _startDistance).clamp(
      minScale / startScale,
      maxScale / startScale,
    );
    node.globalTransform =
        vm.Matrix4.translation((a + b)..scale(0.5)) *
        vm.Matrix4.diagonal3Values(factor, factor, factor) *
        vm.Matrix4.translation(-_startMidpoint!) *
        _start!;
  }

  // Moves the held node along the hand's aim ray (its -Z) by a stick
  // deflection already scaled by the frame time.
  void _push(double deflectionSeconds) {
    final distance = -_targetFromHand!.getTranslation().z;
    final speed = math.max(_pushMinimumSpeed, distance * _pushRate);
    final target = math.max(distance + deflectionSeconds * speed, _closest);
    _targetFromHand =
        vm.Matrix4.translationValues(0, 0, distance - target) *
        _targetFromHand!;
  }

  void _trackRelease(Node node, double now, bool wasHolding) {
    if (holding) {
      if (!wasHolding) {
        _trail.clear();
        onGrab?.call();
      }
      _trail.add((now, node.globalTransform.getTranslation()));
      while (_trail.length > 2 && now - _trail.first.$1 > _throwWindow) {
        _trail.removeAt(0);
      }
    } else if (wasHolding) {
      onRelease?.call(_releaseVelocity());
      _trail.clear();
    }
  }

  vm.Vector3 _releaseVelocity() {
    if (_trail.length < 2) return vm.Vector3.zero();
    final (t0, p0) = _trail.first;
    final (t1, p1) = _trail.last;
    final dt = t1 - t0;
    return dt <= 0 ? vm.Vector3.zero() : ((p1 - p0)..scale(1 / dt));
  }

  void _letGo() {
    _trail.clear();
    _holding.fillRange(0, 2, false);
    _targetFromHand = _start = _startMidpoint = null;
  }

  void _capture(Node node, List<vm.Matrix4?> hands) {
    _targetFromHand = _start = _startMidpoint = null;
    final global = node.globalTransform.clone();
    if (_holding[0] && _holding[1]) {
      final a = hands[0]!.getTranslation();
      final b = hands[1]!.getTranslation();
      // Coincident controllers would divide by zero; treat them as 1 cm apart.
      _startDistance = math.max(a.distanceTo(b), 0.01);
      _startMidpoint = (a + b)..scale(0.5);
      _start = global;
    } else if (holding) {
      _targetFromHand =
          vm.Matrix4.inverted(hands[_holding[0] ? 0 : 1]!) * global;
    }
  }

  // The controller touches the node's bounding sphere, or its aim ray meets
  // it, with [reach] of slack.
  bool _hits(Node node, vm.Matrix4 hand) {
    final sphere = _worldSphere(node);
    final origin = hand.getTranslation();
    final direction = (hand.transformed3(vm.Vector3(0, 0, -1)) - origin)
      ..normalize();
    final toCenter = sphere.center - origin;
    final radius = sphere.radius + reach;
    if (toCenter.length2 <= radius * radius) return true;
    final along = toCenter.dot(direction);
    return along >= 0 && toCenter.length2 - along * along <= radius * radius;
  }

  vm.Sphere _worldSphere(Node node) {
    vm.Sphere? bounds;
    for (final meshNode in node.meshNodes) {
      final sphere = openXrMeshWorldSphere(meshNode);
      if (sphere == null) continue;
      bounds = bounds == null ? sphere : _enclose(bounds, sphere);
    }
    // Nothing measurable yet (still loading): a 30 cm ball at the origin.
    return bounds ??
        vm.Sphere.centerRadius(node.globalTransform.getTranslation(), 0.3);
  }

  // The smallest sphere containing both.
  static vm.Sphere _enclose(vm.Sphere a, vm.Sphere b) {
    final offset = b.center - a.center;
    final distance = offset.length;
    if (distance + b.radius <= a.radius) return a;
    if (distance + a.radius <= b.radius) return b;
    final radius = (distance + a.radius + b.radius) / 2;
    final center = a.center + offset * ((radius - a.radius) / distance);
    return vm.Sphere.centerRadius(center, radius);
  }
}
