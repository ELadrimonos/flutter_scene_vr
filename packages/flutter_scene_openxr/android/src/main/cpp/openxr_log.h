#pragma once

#include <android/log.h>
#include <openxr/openxr.h>

// Logging shared by the OpenXR host and its helpers, under one logcat tag.
inline constexpr char kOpenXrLogTag[] = "FlutterSceneOpenXR";

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, kOpenXrLogTag, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, kOpenXrLogTag, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, kOpenXrLogTag, __VA_ARGS__)

// Returns whether [result] succeeded, logging [operation] as an error if not.
inline bool CheckXr(XrResult result, const char* operation) {
    if (XR_SUCCEEDED(result)) return true;
    LOGE("%s failed with OpenXR result %d", operation, result);
    return false;
}
