#!/usr/bin/env bash
set -euo pipefail

# Steam Frame (Lepton) wrapper around the Quest local-forks helper.
# Start "Lepton Development" on the headset first, so adb has a container
# to connect to. Override FRAME_ADB_TARGET with the headset's IP if the
# default hostname does not resolve. Over USB, adb reaches the native Linux
# OS, so run `adb forward tcp:5555 tcp:5555` and use localhost:5555.

frame_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
frame_root="$(cd "$frame_script_dir/../../../.." && pwd)"
frame_adb_target="${FRAME_ADB_TARGET:-frame:5555}"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
# Gradle needs a full JDK (javac, jlink); a JRE-only system Java fails.
if [[ -z "${JAVA_HOME:-}" ]]; then
	for frame_jdk in "$HOME"/.jdks/jdk-21*; do
		[[ -x "$frame_jdk/bin/javac" ]] && export JAVA_HOME="$frame_jdk"
	done
fi

export QUEST_FLUTTER="${QUEST_FLUTTER:-$frame_root/flutter_vr/bin/flutter}"
export QUEST_LOCAL_ENGINE_SRC_PATH="${QUEST_LOCAL_ENGINE_SRC_PATH:-$frame_root/flutter_vr/engine/src}"
export QUEST_LOCAL_ENGINE="${QUEST_LOCAL_ENGINE:-android_profile_arm64}"
export QUEST_LOCAL_ENGINE_HOST="${QUEST_LOCAL_ENGINE_HOST:-host_profile}"

adb connect "$frame_adb_target"
if ! adb -s "$frame_adb_target" get-state >/dev/null 2>&1; then
	printf 'No Lepton container answered at %s. Launch "Lepton Development" on the Frame.\n' \
		"$frame_adb_target" >&2
	exit 1
fi
# A preset serial makes the Quest helper skip its USB/Quest model filter.
export ANDROID_SERIAL="$frame_adb_target"

exec "$frame_script_dir/quest-build-and-deploy-local-forks.sh"
