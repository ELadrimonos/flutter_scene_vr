import 'package:vector_math/vector_math.dart' as vm;

import 'example_chrome.dart' show galleryGrabbableNodeName;

/// What the headset gallery tells an example about its grabbable node (the
/// one named [galleryGrabbableNodeName]).
///
/// The gallery owns the hands: it moves the node while a grip holds it and
/// reports the A/X button. The example owns everything else, such as letting
/// the node fall once released. Flat mode never touches this, so a flat
/// example sees a node that is never held and never frozen.
class GalleryGrabbable {
  /// A hand is moving the node; the example should leave it alone.
  bool held = false;

  /// The A/X button toggled the node to stay where it is, ignoring gravity.
  bool frozen = false;

  /// World-space velocity (m/s) at the moment of release, for a throw.
  /// The example takes it with [takeReleaseVelocity].
  vm.Vector3? _releaseVelocity;

  void grab() {
    held = true;
    _releaseVelocity = null;
  }

  void release(vm.Vector3 velocity) {
    held = false;
    _releaseVelocity = velocity.clone();
  }

  void togglePrimary() => frozen = !frozen;

  /// Returns the pending release velocity once, then null.
  vm.Vector3? takeReleaseVelocity() {
    final velocity = _releaseVelocity;
    _releaseVelocity = null;
    return velocity;
  }

  void reset() {
    held = false;
    frozen = false;
    _releaseVelocity = null;
  }
}

/// The single grabbable shared by the gallery and the current example.
final galleryGrabbable = GalleryGrabbable();
