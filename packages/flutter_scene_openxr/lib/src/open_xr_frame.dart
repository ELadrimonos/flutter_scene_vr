import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import 'open_xr_eye_view.dart';
import 'open_xr_controller_state.dart';

/// A matched left/right view sample from one native OpenXR frame.
class OpenXrFrame {
  const OpenXrFrame({
    required this.sequence,
    required this.leftEye,
    required this.rightEye,
    required this.controllers,
    this.uiPaused = false,
    this.panelHits,
    this.panelPlacements,
    this.navigation,
  });

  factory OpenXrFrame.fromPlatform(Object? payload) {
    final values = switch (payload) {
      Float64List value => value,
      List<Object?> value => Float64List.fromList(
        value.map((entry) => (entry as num).toDouble()).toList(),
      ),
      _ => throw const FormatException(
        'OpenXR view update must be a packed list of doubles.',
      ),
    };

    // Layout extensions append controller and panel data to the original eyes.
    // Accept only known lengths so a mismatched bridge cannot silently shift
    // pose fields; PublishViews in the native host owns the matching offsets.
    if (!const {
      _packedValueCount,
      _controllersValueCount,
      _controllersValueCount + _inputTailLength,
      _panelsValueCount,
      _panelPosesValueCount + _inputTailLength,
    }.contains(values.length)) {
      throw FormatException(
        'OpenXR view update contained ${values.length} values; '
        'expected $_packedValueCount.',
      );
    }

    final hasPanels = values.length >= _panelsValueCount;
    final hasPanelPoses = values.length > _panelPosesValueCount;
    // The input tail (scene grips, then primary buttons) closes the packet.
    final hasTail =
        values.length > _panelPosesValueCount ||
        values.length == _controllersValueCount + _inputTailLength;
    final tail = values.length - _inputTailLength;
    double grip(int hand) => hasTail ? values[tail + hand] : 0.0;
    bool primary(int hand) => hasTail && values[tail + 2 + hand] != 0;
    return OpenXrFrame(
      sequence: values[0].toInt(),
      uiPaused: hasPanels && values[45] != 0,
      panelHits: hasPanels
          ? [
              for (final offset in [46, 49])
                values[offset] < 0
                    ? null
                    : OpenXrPanelHit(
                        panel: values[offset].toInt(),
                        position: vm.Vector2(
                          values[offset + 1],
                          values[offset + 2],
                        ),
                      ),
            ]
          : null,
      panelPlacements: hasPanelPoses
          ? [
              for (var index = 0; index < 2; index++)
                if (values[_panelPosesOffset + index * _panelPoseStride] != 0)
                  _panelPlacementFrom(values, index),
            ]
          : null,
      navigation: hasPanels
          ? OpenXrControllerState(
              leftThumbstick: vm.Vector2(values[52], values[53]),
              rightThumbstick: vm.Vector2(values[54], values[55]),
            )
          : null,
      leftEye: _eyeFrom(values, _leftEyeOffset),
      rightEye: _eyeFrom(values, _rightEyeOffset),
      controllers: OpenXrControllerState(
        aims: values.length < _controllersValueCount
            ? const []
            : [
                for (final (hand, offset) in [(0, 27), (1, 36)])
                  OpenXrControllerAim(
                    position: vm.Vector3(
                      values[offset],
                      values[offset + 1],
                      values[offset + 2],
                    ),
                    orientation: vm.Quaternion(
                      values[offset + 3],
                      values[offset + 4],
                      values[offset + 5],
                      values[offset + 6],
                    ),
                    tracked: values[offset + 7] != 0,
                    trigger: values[offset + 8],
                    grip: grip(hand),
                    primaryButton: primary(hand),
                  ),
              ],
        leftThumbstick: vm.Vector2(
          values[_leftThumbstickOffset],
          values[_leftThumbstickOffset + 1],
        ),
        rightThumbstick: vm.Vector2(
          values[_rightThumbstickOffset],
          values[_rightThumbstickOffset + 1],
        ),
      ),
    );
  }

  /// A head-relative stereo sample used until LOCAL-space tracking arrives.
  factory OpenXrFrame.preview() {
    const halfIpd = 0.032;
    const halfFov = math.pi / 4;
    const fieldOfView = OpenXrFieldOfView(
      angleLeft: -halfFov,
      angleRight: halfFov,
      angleUp: halfFov,
      angleDown: -halfFov,
    );

    return OpenXrFrame(
      sequence: 0,
      leftEye: OpenXrEyeView(
        position: vm.Vector3(-halfIpd, 0, 0),
        orientation: vm.Quaternion.identity(),
        fieldOfView: fieldOfView,
      ),
      rightEye: OpenXrEyeView(
        position: vm.Vector3(halfIpd, 0, 0),
        orientation: vm.Quaternion.identity(),
        fieldOfView: fieldOfView,
      ),
      controllers: OpenXrControllerState.idle(),
    );
  }

  final int sequence;
  final OpenXrEyeView leftEye;
  final OpenXrEyeView rightEye;
  final OpenXrControllerState controllers;
  final bool uiPaused;

  /// Logical atlas hits computed from the same poses as the compositor panels.
  /// Null means the older single-quad host; null entries mean no UI hit.
  final List<OpenXrPanelHit?>? panelHits;

  /// Where the host's floating UI panels are, in the same LOCAL space as the
  /// eyes. Null on hosts that do not report them.
  final List<OpenXrPanelPlacement>? panelPlacements;

  /// Sticks after native panel, grip and FPS-button arbitration.
  final OpenXrControllerState? navigation;

  static const _packedValueCount = 27;
  // Eyes plus both controller aims.
  static const _controllersValueCount = 45;
  // Plus the panel block: pause flag, two hits, arbitrated sticks.
  static const _panelsValueCount = 56;
  // Plus, per panel: visible flag, position, orientation, width, height.
  static const _panelPosesOffset = _panelsValueCount;
  static const _panelPoseStride = 10;
  static const _panelPosesValueCount = _panelPosesOffset + 2 * _panelPoseStride;
  // Closes newer packets: two scene grips, then two primary buttons.
  static const _inputTailLength = 4;
  static const _leftEyeOffset = 1;
  static const _rightEyeOffset = 12;
  static const _leftThumbstickOffset = 23;
  static const _rightThumbstickOffset = 25;

  static OpenXrPanelPlacement _panelPlacementFrom(
    Float64List values,
    int index,
  ) {
    final at = _panelPosesOffset + index * _panelPoseStride;
    return OpenXrPanelPlacement(
      index: index,
      position: vm.Vector3(values[at + 1], values[at + 2], values[at + 3]),
      orientation: vm.Quaternion(
        values[at + 4],
        values[at + 5],
        values[at + 6],
        values[at + 7],
      ),
      width: values[at + 8],
      height: values[at + 9],
    );
  }

  static OpenXrEyeView _eyeFrom(Float64List values, int offset) {
    return OpenXrEyeView(
      position: vm.Vector3(
        values[offset],
        values[offset + 1],
        values[offset + 2],
      ),
      orientation: vm.Quaternion(
        values[offset + 3],
        values[offset + 4],
        values[offset + 5],
        values[offset + 6],
      ),
      fieldOfView: OpenXrFieldOfView(
        angleLeft: values[offset + 7],
        angleRight: values[offset + 8],
        angleUp: values[offset + 9],
        angleDown: values[offset + 10],
      ),
    );
  }
}

/// A floating UI panel: a quad centred on [position], facing its local +Z.
class OpenXrPanelPlacement {
  const OpenXrPanelPlacement({
    required this.index,
    required this.position,
    required this.orientation,
    required this.width,
    required this.height,
  });

  /// Which host panel this is (0 or 1), stable while panels hide and show.
  final int index;
  final vm.Vector3 position;
  final vm.Quaternion orientation;
  final double width;
  final double height;
}

/// A hit on one independently positioned crop of the Flutter atlas.
class OpenXrPanelHit {
  const OpenXrPanelHit({required this.panel, required this.position});
  final int panel;
  final vm.Vector2 position;
}
