#pragma once

#include <cstddef>
#include <iterator>

// Controller bindings, as data. Each supported controller is an OpenXR
// interaction profile mapping the host's actions to its input paths. Adding a
// controller or moving an action to another button only touches this file.
namespace openxr_input {

// The host's actions. ControllerInput creates one per entry, for both hands.
enum class Action {
    thumbstick,     // Vector2: panel scrolling and scene navigation.
    aim,            // Pose: the pointing ray for panels and scene picking.
    trigger,        // Float: select.
    grip,           // Float: grab panels and scene objects.
    primaryButton,  // Boolean: per-example action (the AR example freezes).
};

struct Binding {
    Action action;
    const char* path;
    // A runtime that rejects an optional path still gets the rest of the
    // profile; the action then simply reads as idle on that controller.
    bool optional = false;
};

struct InteractionProfile {
    const char* path;
    // Instance extension the profile needs, or null for core profiles. A core
    // profile that the runtime rejects is fatal; an extension one is skipped.
    const char* extension;
    const Binding* bindings;
    std::size_t bindingCount;
};

// Meta Quest Touch. Also the fallback other runtimes remap onto their own
// controllers when the app suggests nothing more specific for them.
inline constexpr Binding kTouchBindings[] = {
    {Action::thumbstick, "/user/hand/left/input/thumbstick"},
    {Action::thumbstick, "/user/hand/right/input/thumbstick"},
    {Action::aim, "/user/hand/left/input/aim/pose"},
    {Action::aim, "/user/hand/right/input/aim/pose"},
    {Action::trigger, "/user/hand/left/input/trigger/value"},
    {Action::trigger, "/user/hand/right/input/trigger/value"},
    {Action::grip, "/user/hand/left/input/squeeze/value"},
    {Action::grip, "/user/hand/right/input/squeeze/value"},
    // The lower face button of each hand.
    {Action::primaryButton, "/user/hand/left/input/x/click", true},
    {Action::primaryButton, "/user/hand/right/input/a/click", true},
};

// Steam Frame Controller (SteamVR on Lepton). Its layout is a gamepad split in
// two: A/B/X/Y all sit on the right controller and a d-pad on the left. The
// primary button is the bottom position of each: d-pad down and A.
inline constexpr Binding kFrameControllerBindings[] = {
    {Action::thumbstick, "/user/hand/left/input/thumbstick"},
    {Action::thumbstick, "/user/hand/right/input/thumbstick"},
    {Action::aim, "/user/hand/left/input/aim/pose"},
    {Action::aim, "/user/hand/right/input/aim/pose"},
    {Action::trigger, "/user/hand/left/input/trigger/value"},
    {Action::trigger, "/user/hand/right/input/trigger/value"},
    {Action::grip, "/user/hand/left/input/squeeze/value"},
    {Action::grip, "/user/hand/right/input/squeeze/value"},
    {Action::primaryButton, "/user/hand/left/input/dpad_down/click", true},
    {Action::primaryButton, "/user/hand/right/input/a/click", true},
};

inline constexpr InteractionProfile kInteractionProfiles[] = {
    {
        "/interaction_profiles/oculus/touch_controller",
        nullptr,
        kTouchBindings,
        std::size(kTouchBindings),
    },
    // Without the extension SteamVR remaps the Touch bindings onto the Frame
    // Controller instead, and the d-pad binding above is not available.
    {
        "/interaction_profiles/valve/frame_controller_valve",
        "XR_VALVE_frame_controller_interaction",
        kFrameControllerBindings,
        std::size(kFrameControllerBindings),
    },
};

}  // namespace openxr_input
