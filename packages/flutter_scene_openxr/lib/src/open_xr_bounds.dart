import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A world-space bounding sphere for one mesh node, or null if unknown.
///
/// A skinned mesh's baked bounds cover its bind pose in an unrelated frame
/// and come out far too large (Dash reports ~1.25 m for a 0.7 m body), so a
/// skinned node is bounded by its joints' current world positions instead,
/// grown by [skinMargin] of their extent for the surface around the bones.
/// That also follows the animation.
vm.Sphere? openXrMeshWorldSphere(Node node, {double skinMargin = 0.25}) {
  final joints = node.skin?.joints.whereType<Node>();
  if (joints != null && joints.isNotEmpty) {
    vm.Aabb3? box;
    for (final joint in joints) {
      final point = joint.globalTransform.getTranslation();
      box == null
          ? box = vm.Aabb3.minMax(point, point.clone())
          : box.hullPoint(point);
    }
    final extent = (box!.max - box.min).length;
    return vm.Sphere.centerRadius(box.center, extent / 2 * (1 + skinMargin));
  }
  final bounds = node.mesh?.localBounds;
  if (bounds == null) return null;
  final world = vm.Aabb3.copy(bounds)..transform(node.globalTransform);
  return vm.Sphere.centerRadius(
    world.center,
    (world.max - world.min).length / 2,
  );
}
