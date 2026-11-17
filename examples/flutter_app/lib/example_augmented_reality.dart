import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'lighting_panel.dart' show LabeledSlider;
import 'example_panel.dart';
import 'example_settings.dart';

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
/// the real floor is.
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
            onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(_scene),
            loadingBuilder: (context, progress) =>
                const Center(child: CircularProgressIndicator()),
            children: [
              SceneModel(
                'assets_src/dash.glb',
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
          onChanged: (v) => setState(() => _floorDrop = v),
        ),
        LabeledSlider(
          label: 'Distance (m)',
          value: _distance,
          min: 0.6,
          max: 4,
          onChanged: (v) => setState(() => _distance = v),
        ),
        LabeledSlider(
          label: 'Size',
          value: _size,
          min: 0.08,
          max: 0.6,
          onChanged: (v) => setState(() => _size = v),
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
