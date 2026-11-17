import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'open_xr_bounds.dart';
import 'open_xr_controller_rays.dart';
import 'open_xr_frame.dart';

/// Keeps passthrough scene content correctly in front of or behind the host's
/// floating UI panels.
///
/// SteamVR composites quad layers above the scene whatever their order, so a
/// panel quad always covers the scene. That is right while nothing is between
/// the viewer and the panel. When something is, the host copies what each eye
/// sees across the panel into a per-eye quad above it; [update] returns which
/// panels need that. The panel itself always stays a sharp compositor quad.
///
/// Each panel also gets an invisible [HoldoutMaterial] quad in the scene. It
/// writes the panel's depth and clears the pixel to alpha 0, so content behind
/// a panel is cut out of the eye images and never reaches the copy above the
/// panel, while content in front of it survives.
class OpenXrPanelOcclusion {
  OpenXrPanelOcclusion(this.scene);

  final Scene scene;

  static const _rootName = 'xr-panel-holdouts';

  // How long a panel keeps its occluder after the last overlap, so content
  // grazing its edge does not flicker in and out.
  static const _holdSeconds = 0.4;

  final _root = Node(name: _rootName);
  final _holdouts = <Node>[];
  final _lastOverlap = <int, double>{};
  final _clock = Stopwatch()..start();

  /// Places the holdouts for this frame's panels and returns the panels, as a
  /// bit per [OpenXrPanelPlacement.index], with visible scene content between
  /// [head] and them. [placements] and [head] are in LOCAL space.
  int update(
    List<OpenXrPanelPlacement>? placements,
    bool uiPaused,
    vm.Vector3 head,
    vm.Matrix4? worldFromReference,
  ) {
    // Some examples replace their scene children when an asset finishes loading.
    if (_root.parent == null) scene.add(_root);
    final reference = worldFromReference ?? vm.Matrix4.identity();
    _root.localTransform = reference;
    // Hidden panels (UI off) must not cut holes in the scene.
    final visible = uiPaused
        ? const <OpenXrPanelPlacement>[]
        : placements ?? const <OpenXrPanelPlacement>[];
    _placeHoldouts(visible);
    if (visible.isEmpty) return 0;

    final now = _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
    final occluders = _occluders(vm.Matrix4.inverted(reference));
    var mask = 0;
    for (final panel in visible) {
      if (occluders.any((sphere) => _inFront(sphere, panel, head))) {
        _lastOverlap[panel.index] = now;
      }
      final last = _lastOverlap[panel.index];
      if (last != null && now - last < _holdSeconds) mask |= 1 << panel.index;
    }
    return mask;
  }

  void dispose() => _root.parent?.remove(_root);

  void _placeHoldouts(List<OpenXrPanelPlacement> panels) {
    while (_holdouts.length < panels.length) {
      final holdout =
          Node(
              name: '$_rootName-${_holdouts.length}',
              mesh: Mesh(
                PlaneGeometry(),
                HoldoutMaterial()..doubleSided = true,
              ),
            )
            ..raycastable = false
            ..shadowCastingMode = ShadowCastingMode.off;
      _holdouts.add(holdout);
      _root.add(holdout);
    }
    for (var i = 0; i < _holdouts.length; i++) {
      final holdout = _holdouts[i];
      holdout.visible = i < panels.length;
      if (!holdout.visible) continue;
      final panel = panels[i];
      // The plane lies in XZ facing +Y; a quarter turn about X makes it face
      // +Z like an OpenXR quad, with its depth axis becoming the height.
      holdout.localTransform =
          vm.Matrix4.compose(
            panel.position,
            panel.orientation,
            vm.Vector3.all(1),
          ) *
          vm.Matrix4.rotationX(math.pi / 2) *
          vm.Matrix4.diagonal3Values(panel.width, 1, panel.height);
    }
  }

  // Bounding spheres, in LOCAL space, of everything that draws visibly: not
  // the holdouts, not the controller rays (UI hints that panels may cover,
  // as in VR), not invisible nodes, and not receivers like shadow catchers.
  List<vm.Sphere> _occluders(vm.Matrix4 referenceFromWorld) {
    final spheres = <vm.Sphere>[];
    void visit(Node node) {
      if (!node.visible ||
          node.name == _rootName ||
          node.name == OpenXrControllerRays.rootName) {
        return;
      }
      final mesh = node.mesh;
      if (mesh != null &&
          mesh.primitives.any(
            (primitive) =>
                primitive.material is! ShadowCatcherMaterial &&
                primitive.material is! HoldoutMaterial,
          )) {
        final world = openXrMeshWorldSphere(node);
        // The reference transform is rigid, so the radius carries over.
        if (world != null) {
          spheres.add(
            vm.Sphere.centerRadius(
              referenceFromWorld.transformed3(world.center),
              world.radius,
            ),
          );
        }
      }
      node.children.forEach(visit);
    }

    visit(scene.root);
    return spheres;
  }

  // Whether any part of [sphere] is on the viewer's side of the panel and,
  // seen from [head], overlaps the panel's rectangle.
  static bool _inFront(
    vm.Sphere sphere,
    OpenXrPanelPlacement panel,
    vm.Vector3 head,
  ) {
    final rotation = panel.orientation;
    final normal = rotation.rotated(vm.Vector3(0, 0, 1));
    final headSide = (head - panel.position).dot(normal);
    if (headSide.abs() < 1e-4) return false; // Viewing the panel edge-on.
    final side = headSide.sign;
    final sphereDistance = (sphere.center - panel.position).dot(normal) * side;
    if (sphereDistance + sphere.radius <= 0) return false; // Fully behind.

    // Project the sphere from the head onto the panel plane.
    final towardSphere = sphere.center - head;
    final along = -towardSphere.dot(normal) * side;
    final vm.Vector3 hit;
    final double radius;
    if (along <= 1e-4) {
      // The centre is level with or behind the head along the normal; the
      // orthogonal footprint is a conservative stand-in.
      hit = sphere.center - normal * (sphereDistance * side);
      radius = sphere.radius;
    } else {
      final t = headSide.abs() / along;
      hit = head + towardSphere * t;
      radius = sphere.radius * math.max(1.0, t);
    }
    final offset = hit - panel.position;
    return offset.dot(rotation.rotated(vm.Vector3(1, 0, 0))).abs() <=
            panel.width / 2 + radius &&
        offset.dot(rotation.rotated(vm.Vector3(0, 1, 0))).abs() <=
            panel.height / 2 + radius;
  }
}
