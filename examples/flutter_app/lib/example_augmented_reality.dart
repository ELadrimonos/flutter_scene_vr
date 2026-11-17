import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_chrome.dart' show galleryGrabbableNodeName;
import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';
import 'gallery_grabbable.dart';
import 'lighting_panel.dart' show LabeledSlider;

/// Dash standing in the viewer's real room.
///
/// In a headset the scene renders over passthrough: the gallery sees this
/// example's name in `galleryPassthroughExamples`, asks the OpenXR host for an
/// alpha-blended environment, and leaves the background transparent. Nothing
/// here paints a backdrop in that mode, so the room shows through every pixel
/// the scene does not cover.
///
/// Flat mode has no camera feed, so it paints a stand-in room behind the
/// transparent scene instead.
///
/// The headset tracking origin is the head's starting position and no plane
/// detection is involved, so the floor height is a slider: set it to where
/// the real floor is. An invisible shadow catcher there puts Dash's shadow on
/// the real floor.
///
/// In a headset the gallery lets controller grips grab Dash (see
/// [galleryGrabbable]); released, he falls and bounces on the floor, keeping
/// the throw's velocity. The primary button freezes him in place. The
/// sliders put him back on the floor.
class ExampleAugmentedReality extends StatefulWidget {
  const ExampleAugmentedReality({super.key});

  @override
  State<ExampleAugmentedReality> createState() =>
      _ExampleAugmentedRealityState();
}

class _ExampleAugmentedRealityState extends State<ExampleAugmentedReality> {
  static const _clips = ['Idle', 'Walk', 'Run'];

  final Scene _scene = Scene();

  String _clip = 'Idle';
  // Metres below the head at which Dash's feet are placed.
  double _floorDrop = 1.5;
  double _distance = 1.6;
  double _size = 0.25;

  // An invisible floor at the real floor's height that draws only Dash's
  // shadow, so the shadow lands on the real floor seen through passthrough.
  // Built on the first tick, once its material's resources exist.
  Node? _floor;

  // Dash falls and bounces on the floor whenever no hand holds him and the
  // primary button has not frozen him in the air.
  final _dash = SceneNodeController();
  final vm.Vector3 _velocity = vm.Vector3.zero();
  static const _gravity = 9.81;
  static const _bounce = 0.55; // Fraction of the speed kept on each bounce.
  static const _restSpeed = 0.35; // Slower bounces than this settle.
  static const _floorFriction = 4.0; // Per second, while sliding on the floor.

  void _tick(Duration elapsed, double deltaSeconds) {
    exampleSettings.applyTo(_scene);
    final floor = _floor ??=
        Node(
            name: 'ar-floor',
            mesh: Mesh(
              PlaneGeometry(width: 8, depth: 8),
              ShadowCatcherMaterial(
                shadowIntensity: 0.7,
                aoStrength: 0.4,
                fadeStart: 2,
                fadeEnd: 4,
              ),
            ),
          )
          ..raycastable = false
          ..shadowCastingMode = ShadowCastingMode.off;
    if (floor.parent == null) _scene.add(floor);
    floor.localTransform = vm.Matrix4.translationValues(0, -_floorDrop, 0);
    _fall(deltaSeconds);
  }

  void _fall(double deltaSeconds) {
    final node = _dash.node;
    if (node == null) return;
    final grab = galleryGrabbable;
    final thrown = grab.takeReleaseVelocity();
    if (thrown != null) _velocity.setFrom(thrown);
    if (grab.held || grab.frozen) {
      if (grab.frozen) _velocity.setZero();
      return;
    }
    // Long hitches (loading, a paused headset) would teleport him.
    final dt = deltaSeconds.clamp(0.0, 1 / 30);
    if (dt == 0) return;
    final floorY = -_floorDrop;
    final position = node.position;
    final onFloor = position.y <= floorY + 1e-4 && _velocity.y <= 0;
    if (onFloor && _velocity.length2 == 0) return; // At rest.

    _velocity.y -= _gravity * dt;
    position.addScaled(_velocity, dt);
    if (position.y < floorY) {
      position.y = floorY;
      _velocity.y = -_velocity.y * _bounce;
      if (_velocity.y < _restSpeed) _velocity.y = 0;
    }
    if (position.y <= floorY + 1e-4 && _velocity.y == 0) {
      final keep = (1 - _floorFriction * dt).clamp(0.0, 1.0);
      _velocity
        ..x *= keep
        ..z *= keep;
      if (_velocity.length2 < 1e-4) _velocity.setZero();
    }
    node.position = position;
  }

  // The sliders re-place Dash through the SceneModel props; start him at rest.
  void _settle() {
    _velocity.setZero();
    galleryGrabbable.frozen = false;
  }

  @override
  void initState() {
    super.initState();
    galleryGrabbable.reset();
  }

  @override
  void dispose() {
    _scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only a headset supplies a replacement presenter; flat mode renders the
    // SceneView in the widget tree and needs its own backdrop.
    final immersive =
        context
            .dependOnInheritedWidgetOfExactType<SceneViewPresentation>()
            ?.present !=
        null;
    return Stack(
      children: [
        if (!immersive) const Positioned.fill(child: _StandInRoom()),
        Positioned.fill(
          child: SceneView(
            _scene,
            camera: PerspectiveCamera(
              position: vm.Vector3.zero(),
              target: vm.Vector3(0, 0, -1),
              fovNear: 0.04,
              fovFar: 50,
            ),
            onTick: _tick,
            loadingBuilder: (context, progress) =>
                const Center(child: CircularProgressIndicator()),
            children: [
              SceneModel(
                'assets_src/dash.glb',
                // Headset grips grab and pinch-scale Dash; the sliders below
                // put him back where they say.
                name: galleryGrabbableNodeName,
                controller: _dash,
                position: vm.Vector3(0, -_floorDrop, -_distance),
                scale: vm.Vector3.all(_size),
                animations: [
                  for (final clip in _clips)
                    SceneAnimationSpec(clip, weight: clip == _clip ? 1 : 0),
                ],
              ),
            ],
          ),
        ),
        ExampleOverlay.bottomLeftPanel(child: _controls()),
      ],
    );
  }

  Widget _controls() => ExamplePanelCard(
    icon: Icons.view_in_ar,
    title: 'Augmented Reality',
    width: 300,
    maxBodyHeight: 340,
    body: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Headset: Dash appears in your room through passthrough. '
          'Grip to grab him, release to drop or throw; while held the '
          'stick pushes or pulls him. Grip with both hands to scale. '
          'A/X (Frame: A or d-pad down) freezes him in the air. '
          'Flat: a stand-in room.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final clip in _clips)
              ChoiceChip(
                label: Text(clip),
                selected: _clip == clip,
                onSelected: (_) => setState(() => _clip = clip),
              ),
          ],
        ),
        LabeledSlider(
          label: 'Floor below head (m)',
          value: _floorDrop,
          min: 0.5,
          max: 2.2,
          onChanged: (v) => setState(() {
            _floorDrop = v;
            _settle();
          }),
        ),
        LabeledSlider(
          label: 'Distance (m)',
          value: _distance,
          min: 0.6,
          max: 4,
          onChanged: (v) => setState(() {
            _distance = v;
            _settle();
          }),
        ),
        LabeledSlider(
          label: 'Size',
          value: _size,
          min: 0.08,
          max: 0.6,
          onChanged: (v) => setState(() {
            _size = v;
            _settle();
          }),
        ),
      ],
    ),
  );
}

/// A flat wall-and-floor gradient so the transparent scene has something
/// behind it when there is no passthrough camera.
class _StandInRoom extends StatelessWidget {
  const _StandInRoom();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xff5c6b7a), Color(0xff8d99a6), Color(0xff4a4036)],
        stops: [0, 0.62, 0.62],
      ),
    ),
  );
}
