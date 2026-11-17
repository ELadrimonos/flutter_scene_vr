#pragma once

#include <openxr/openxr.h>

#include <array>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <iterator>
#include <optional>
#include <vector>

#include "openxr_interaction_profiles.h"
#include "openxr_log.h"

namespace openxr_input {

// One frame of controller input, both hands sampled in the same space and at
// the same predicted time as the eyes.
struct ControllerSample {
    // Dead zone already applied.
    std::array<XrVector2f, 2> thumbsticks{};
    // Per hand: aim position xyz, orientation xyzw, tracked (0 or 1), trigger.
    // Panel hit testing and the Dart bridge consume this layout directly.
    std::array<double, 18> aims{};
    std::array<float, 2> grips{};
    std::array<bool, 2> primaryButtons{};
};

// Owns the OpenXR action set: creates the host's actions, suggests the
// bindings of every supported controller (see openxr_interaction_profiles.h)
// and samples them once per frame.
class ControllerInput {
public:
    // Adds the instance extensions of the interaction profiles the runtime
    // offers. Call before creating the instance; [available] answers whether
    // the runtime offers an extension by name.
    template <typename Available>
    void RequestExtensions(const Available& available, std::vector<const char*>& extensions) {
        for (const InteractionProfile& profile : kInteractionProfiles) {
            if (profile.extension == nullptr || !available(profile.extension)) continue;
            extensions.push_back(profile.extension);
            enabledExtensions_.push_back(profile.extension);
        }
    }

    bool Create(XrInstance instance, XrSession session) {
        instance_ = instance;
        session_ = session;
        XrActionSetCreateInfo setInfo{XR_TYPE_ACTION_SET_CREATE_INFO};
        std::strncpy(setInfo.actionSetName, "flutter_scene", XR_MAX_ACTION_SET_NAME_SIZE - 1);
        std::strncpy(setInfo.localizedActionSetName, "Flutter Scene",
                     XR_MAX_LOCALIZED_ACTION_SET_NAME_SIZE - 1);
        if (!CheckXr(xrCreateActionSet(instance_, &setInfo, &actionSet_), "xrCreateActionSet") ||
            !CheckXr(xrStringToPath(instance_, "/user/hand/left", &handPaths_[0]), "left hand path") ||
            !CheckXr(xrStringToPath(instance_, "/user/hand/right", &handPaths_[1]), "right hand path")) {
            return false;
        }
        for (const ActionSpec& spec : kActionSpecs) {
            XrActionCreateInfo info{XR_TYPE_ACTION_CREATE_INFO};
            info.actionType = spec.type;
            std::strncpy(info.actionName, spec.name, XR_MAX_ACTION_NAME_SIZE - 1);
            std::strncpy(info.localizedActionName, spec.localizedName,
                         XR_MAX_LOCALIZED_ACTION_NAME_SIZE - 1);
            info.countSubactionPaths = handPaths_.size();
            info.subactionPaths = handPaths_.data();
            if (!CheckXr(xrCreateAction(actionSet_, &info, &ActionHandle(spec.action)), spec.name)) {
                return false;
            }
        }
        for (std::size_t hand = 0; hand < 2; ++hand) {
            XrActionSpaceCreateInfo spaceInfo{XR_TYPE_ACTION_SPACE_CREATE_INFO};
            spaceInfo.action = ActionHandle(Action::aim);
            spaceInfo.subactionPath = handPaths_[hand];
            spaceInfo.poseInActionSpace.orientation.w = 1;
            if (!CheckXr(xrCreateActionSpace(session_, &spaceInfo, &aimSpaces_[hand]),
                         "xrCreateActionSpace(aim)")) {
                return false;
            }
        }
        if (!SuggestBindings()) return false;
        XrSessionActionSetsAttachInfo attachInfo{XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};
        attachInfo.countActionSets = 1;
        attachInfo.actionSets = &actionSet_;
        return CheckXr(xrAttachSessionActionSets(session_, &attachInfo), "xrAttachSessionActionSets");
    }

    // Destroying the action set also destroys its actions.
    void Destroy() {
        for (XrSpace& space : aimSpaces_) {
            if (space != XR_NULL_HANDLE) xrDestroySpace(space);
            space = XR_NULL_HANDLE;
        }
        if (actionSet_ != XR_NULL_HANDLE) xrDestroyActionSet(actionSet_);
        actionSet_ = XR_NULL_HANDLE;
        actions_ = {};
        session_ = XR_NULL_HANDLE;
        instance_ = XR_NULL_HANDLE;
    }

    // Syncs the actions and reads both hands. Everything reads as idle while
    // the session is not focused, since the runtime then withholds input.
    ControllerSample Sample(XrSpace space, XrTime time, bool sessionFocused) {
        ControllerSample sample;
        XrActiveActionSet active{actionSet_, XR_NULL_PATH};
        XrActionsSyncInfo syncInfo{XR_TYPE_ACTIONS_SYNC_INFO};
        syncInfo.countActiveActionSets = 1;
        syncInfo.activeActionSets = &active;
        if (xrSyncActions(session_, &syncInfo) != XR_SUCCESS || !sessionFocused) return sample;

        for (std::size_t hand = 0; hand < 2; ++hand) {
            const XrVector2f stick = ReadVector2(Action::thumbstick, hand);
            sample.thumbsticks[hand] = {ApplyDeadzone(stick.x), ApplyDeadzone(stick.y)};
            sample.grips[hand] = ReadFloat(Action::grip, hand);
            sample.primaryButtons[hand] = ReadBool(Action::primaryButton, hand);

            const std::optional<XrPosef> aim = ReadAim(hand, space, time);
            if (!aim) continue;
            double* values = sample.aims.data() + hand * 9;
            values[0] = aim->position.x;
            values[1] = aim->position.y;
            values[2] = aim->position.z;
            values[3] = aim->orientation.x;
            values[4] = aim->orientation.y;
            values[5] = aim->orientation.z;
            values[6] = aim->orientation.w;
            values[7] = 1;
            values[8] = ReadFloat(Action::trigger, hand);
        }
        return sample;
    }

private:
    struct ActionSpec {
        Action action;
        XrActionType type;
        // Runtimes persist user rebinding by these names; keep them stable.
        const char* name;
        const char* localizedName;
    };

    static constexpr ActionSpec kActionSpecs[] = {
        {Action::thumbstick, XR_ACTION_TYPE_VECTOR2F_INPUT, "thumbsticks", "Thumbsticks"},
        {Action::aim, XR_ACTION_TYPE_POSE_INPUT, "ui_aim", "UI aim"},
        {Action::trigger, XR_ACTION_TYPE_FLOAT_INPUT, "ui_trigger", "UI trigger"},
        {Action::grip, XR_ACTION_TYPE_FLOAT_INPUT, "panel_grip", "Move floating panel"},
        {Action::primaryButton, XR_ACTION_TYPE_BOOLEAN_INPUT, "primary_button", "Primary button"},
    };
    static constexpr std::size_t kActionCount = std::size(kActionSpecs);

    static constexpr float kThumbstickDeadzone = 0.22f;

    // Rescales the live range past the dead zone back to [0, 1].
    static float ApplyDeadzone(float value) {
        const float magnitude = std::abs(value);
        if (magnitude <= kThumbstickDeadzone) return 0;
        return std::copysign((magnitude - kThumbstickDeadzone) / (1 - kThumbstickDeadzone), value);
    }

    XrAction& ActionHandle(Action action) { return actions_[static_cast<std::size_t>(action)]; }
    XrAction ActionHandle(Action action) const { return actions_[static_cast<std::size_t>(action)]; }

    bool ExtensionEnabled(const char* extension) const {
        for (const char* enabled : enabledExtensions_) {
            if (std::strcmp(enabled, extension) == 0) return true;
        }
        return false;
    }

    // Suggests every profile whose extension is enabled. A profile whose
    // optional paths the runtime rejects is retried without them.
    bool SuggestBindings() {
        for (const InteractionProfile& profile : kInteractionProfiles) {
            if (profile.extension != nullptr && !ExtensionEnabled(profile.extension)) continue;
            XrPath profilePath = XR_NULL_PATH;
            std::vector<XrActionSuggestedBinding> all;
            std::vector<XrActionSuggestedBinding> required;
            if (!CheckXr(xrStringToPath(instance_, profile.path, &profilePath), profile.path) ||
                !ResolveBindings(profile, all, required)) {
                return false;
            }
            XrResult result = Suggest(profilePath, all);
            if (XR_SUCCEEDED(result)) {
                LOGI("Suggested %s bindings", profile.path);
                continue;
            }
            if (required.size() < all.size()) {
                LOGW("%s rejected its optional bindings (OpenXR result %d); suggesting the rest",
                     profile.path, result);
                result = Suggest(profilePath, required);
                if (XR_SUCCEEDED(result)) continue;
            }
            LOGE("%s rejected its bindings (OpenXR result %d)", profile.path, result);
            if (profile.extension == nullptr) return false;
        }
        return true;
    }

    bool ResolveBindings(const InteractionProfile& profile,
                         std::vector<XrActionSuggestedBinding>& all,
                         std::vector<XrActionSuggestedBinding>& required) const {
        for (std::size_t i = 0; i < profile.bindingCount; ++i) {
            const Binding& binding = profile.bindings[i];
            XrActionSuggestedBinding suggested{ActionHandle(binding.action), XR_NULL_PATH};
            if (!CheckXr(xrStringToPath(instance_, binding.path, &suggested.binding), binding.path)) {
                return false;
            }
            all.push_back(suggested);
            if (!binding.optional) required.push_back(suggested);
        }
        return true;
    }

    XrResult Suggest(XrPath profile, const std::vector<XrActionSuggestedBinding>& bindings) const {
        XrInteractionProfileSuggestedBinding suggested{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
        suggested.interactionProfile = profile;
        suggested.countSuggestedBindings = static_cast<uint32_t>(bindings.size());
        suggested.suggestedBindings = bindings.data();
        return xrSuggestInteractionProfileBindings(instance_, &suggested);
    }

    XrActionStateGetInfo StateInfo(Action action, std::size_t hand) const {
        XrActionStateGetInfo info{XR_TYPE_ACTION_STATE_GET_INFO};
        info.action = ActionHandle(action);
        info.subactionPath = handPaths_[hand];
        return info;
    }

    float ReadFloat(Action action, std::size_t hand) const {
        const XrActionStateGetInfo info = StateInfo(action, hand);
        XrActionStateFloat state{XR_TYPE_ACTION_STATE_FLOAT};
        return XR_SUCCEEDED(xrGetActionStateFloat(session_, &info, &state)) && state.isActive
            ? state.currentState
            : 0;
    }

    bool ReadBool(Action action, std::size_t hand) const {
        const XrActionStateGetInfo info = StateInfo(action, hand);
        XrActionStateBoolean state{XR_TYPE_ACTION_STATE_BOOLEAN};
        return XR_SUCCEEDED(xrGetActionStateBoolean(session_, &info, &state)) && state.isActive &&
            state.currentState == XR_TRUE;
    }

    XrVector2f ReadVector2(Action action, std::size_t hand) const {
        const XrActionStateGetInfo info = StateInfo(action, hand);
        XrActionStateVector2f state{XR_TYPE_ACTION_STATE_VECTOR2F};
        return XR_SUCCEEDED(xrGetActionStateVector2f(session_, &info, &state)) && state.isActive
            ? state.currentState
            : XrVector2f{};
    }

    // The aim pose in [space], if the controller is active and fully tracked.
    std::optional<XrPosef> ReadAim(std::size_t hand, XrSpace space, XrTime time) const {
        const XrActionStateGetInfo info = StateInfo(Action::aim, hand);
        XrActionStatePose state{XR_TYPE_ACTION_STATE_POSE};
        XrSpaceLocation location{XR_TYPE_SPACE_LOCATION};
        constexpr XrSpaceLocationFlags kValid =
            XR_SPACE_LOCATION_POSITION_VALID_BIT | XR_SPACE_LOCATION_ORIENTATION_VALID_BIT;
        if (XR_FAILED(xrGetActionStatePose(session_, &info, &state)) || !state.isActive ||
            XR_FAILED(xrLocateSpace(aimSpaces_[hand], space, time, &location)) ||
            (location.locationFlags & kValid) != kValid) {
            return std::nullopt;
        }
        return location.pose;
    }

    XrInstance instance_ = XR_NULL_HANDLE;
    XrSession session_ = XR_NULL_HANDLE;
    XrActionSet actionSet_ = XR_NULL_HANDLE;
    std::array<XrAction, kActionCount> actions_{};
    std::array<XrPath, 2> handPaths_{XR_NULL_PATH, XR_NULL_PATH};
    std::array<XrSpace, 2> aimSpaces_{XR_NULL_HANDLE, XR_NULL_HANDLE};
    std::vector<const char*> enabledExtensions_;
};

}  // namespace openxr_input
