import 'dart:typed_data';

import 'package:flutter_scene_openxr/src/open_xr_frame.dart';
import 'package:flutter_test/flutter_test.dart';

// Packets laid out like PublishViews in the native host: 27 eye/stick
// values, 18 controller-aim values, then the optional panel block (11),
// panel poses (20) and input tail (grips, then primary buttons).
Float64List packet({bool panels = false, bool tail = true}) {
  final values = <double>[
    7, // Sequence.
    for (var eye = 0; eye < 2; eye++) ...[0, 0, 0, 0, 0, 0, 1, -1, 1, 1, -1],
    0, 0, 0, 0, // Thumbsticks.
    for (var hand = 0; hand < 2; hand++) ...[0, 0, 0, 0, 0, 0, 1, 1, 0.25],
    if (panels) ...[
      0, // UI not paused.
      -1, 0, 0, -1, 0, 0, // No panel hits.
      0, 0, 0, 0, // Arbitrated sticks.
      // Panel 0 visible, panel 1 hidden.
      1, 0.5, 1.2, -1.5, 0, 0, 0, 1, 0.6, 0.8,
      0, 0, 0, 0, 0, 0, 0, 1, 0, 0,
    ],
    if (tail) ...[0.9, 0.1, 1, 0],
  ];
  return Float64List.fromList(values);
}

void main() {
  test('reads the input tail after the controller aims', () {
    final frame = OpenXrFrame.fromPlatform(packet());
    expect(frame.sequence, 7);
    expect(frame.controllers.aims, hasLength(2));
    expect(frame.controllers.aims[0].grip, 0.9);
    expect(frame.controllers.aims[1].grip, closeTo(0.1, 1e-9));
    expect(frame.controllers.aims[0].primaryButton, isTrue);
    expect(frame.controllers.aims[1].primaryButton, isFalse);
    expect(frame.panelPlacements, isNull);
  });

  test('reads panel placements and keeps hidden panels out', () {
    final frame = OpenXrFrame.fromPlatform(packet(panels: true));
    final placements = frame.panelPlacements!;
    expect(placements, hasLength(1));
    final panel = placements.single;
    expect(panel.index, 0);
    // vector_math stores 32-bit floats.
    expect(panel.position.x, closeTo(0.5, 1e-6));
    expect(panel.position.y, closeTo(1.2, 1e-6));
    expect(panel.position.z, closeTo(-1.5, 1e-6));
    expect(panel.orientation.w, closeTo(1, 1e-6));
    expect(panel.width, 0.6);
    expect(panel.height, 0.8);
    expect(frame.controllers.aims[0].grip, 0.9);
    expect(frame.uiPaused, isFalse);
  });

  test('accepts older packets without the input tail', () {
    final frame = OpenXrFrame.fromPlatform(packet(tail: false));
    expect(frame.controllers.aims[0].grip, 0);
    expect(frame.controllers.aims[0].primaryButton, isFalse);
  });

  test('rejects packets of unknown length', () {
    final values = packet().toList()..removeLast();
    expect(
      () => OpenXrFrame.fromPlatform(Float64List.fromList(values)),
      throwsFormatException,
    );
  });
}
