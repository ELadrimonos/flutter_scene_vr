import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/physically_based_material.dart'
    show AlphaMode;
import 'package:flutter_scene/src/material/unlit_material.dart';

/// An invisible surface that cuts a transparent hole through the scene.
///
/// Wherever its geometry is the nearest surface, the pixel becomes fully
/// transparent black (color and alpha 0) and takes the surface's depth, so
/// scene content behind it disappears while content in front still draws.
/// Over a transparent background, whatever is composited *under* the scene
/// shows through the hole: a passthrough camera feed, or a compositor layer
/// such as a floating UI panel. Give a holdout the shape of that real or
/// layered object and the scene appears to sit correctly behind it.
///
/// It draws in the translucent pass, after every opaque object, with
/// blending that replaces the destination instead of mixing with it, and it
/// writes depth. Give holdout nodes `ShadowCastingMode.off`, since a holdout
/// has no visible body to cast from.
/// {@category Materials}
class HoldoutMaterial extends UnlitMaterial {
  HoldoutMaterial() {
    alphaMode = AlphaMode.blend;
  }

  static final gpu.ColorBlendEquation _replaceWithZero = gpu.ColorBlendEquation(
    colorBlendOperation: gpu.BlendOperation.add,
    sourceColorBlendFactor: gpu.BlendFactor.zero,
    destinationColorBlendFactor: gpu.BlendFactor.zero,
    alphaBlendOperation: gpu.BlendOperation.add,
    sourceAlphaBlendFactor: gpu.BlendFactor.zero,
    destinationAlphaBlendFactor: gpu.BlendFactor.zero,
  );

  @override
  gpu.ColorBlendEquation? get colorBlendEquation => _replaceWithZero;

  @override
  bool get translucentDepthWrite => true;
}
