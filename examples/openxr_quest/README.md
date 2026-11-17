# Quest library gallery

The local-forks helper now launches the library's actual example gallery through
the existing direct OpenXR eye-swapchain renderer:

```sh
cd /Users/adrian/Projects/flutter_scene_vr
./examples/openxr_quest/tool/quest-build-and-deploy-local-forks.sh
```

The selector opens on entry. Aim either controller at an item and pull its trigger;
use the thumbstick while pointing at the list to scroll. **Controls** shows
the selected example's Flutter controls; **Examples** returns to the list.
**Settings** exposes the same global rendering controls as the web gallery.
The performance panel stays on the right. Example switches pause new eye requests
and drain or discard queued frames before replacing the scene, keeping the
immersive activity and selector alive while the next example loads. **Flat mode** retains the selection and
restarts its authored defaults on the same device. Entering VR does the same;
slider state is not transferred between the separate Android processes.

The original demo is the **VR** option in the same gallery, including the normal
flat gallery. `main.dart` is the only launcher; the Quest folder is just the Android
host. `QUEST_SHADOWS=0` starts VR with shadows off; other entries retain authored
lighting and quality. In **VR → Controls**, the **Enable shadows** checkbox
changes the existing light immediately. The same scrollable card explains sticks,
trigger clicks, panel grip/push/pull, reset buttons, scene selection and the FPS toggle.

Left stick rotates around the initial camera target. Right stick moves the camera
and target together. Head tracking remains independent. Aim at either panel and
hold grip to move it; the same hand's stick pushes it away or pulls it closer.
Panels stay where released. The panel-reset icon restores their initial placement.
Point away from panels to navigate; pointing at UI reserves the stick for scrolling.

Thin cyan and lavender rays follow the left and right controller aim poses. Their
tips mark the end of a short beam, not a surface hit; squeezing the trigger turns
the ray white. These are unlit 3D scene meshes, so they remain visible with UI OFF.
Untracked controllers hide their rays; changing examples removes the old meshes.

Aim and trigger the small native **FPS / UI ON** button at the upper right,
above the performance panel's default position, to suspend
all Flutter UI. **UI OFF** removes both large panels, skips framework frame callbacks
(tickers, build, layout, paint), and bypasses panel texture latching and copying.
The native GPU button remains clickable and shows completed stereo FPS, updated
once per second. Trigger again to restore the same mounted UI, example, and graph.
Stats still collect into the bounded 30-second history; teal graph bands identify
UI OFF samples. One already-started UI frame/capture may finish at the transition.

The Dart isolate, Flutter GPU/Scene renderer, scene simulation, platform channels,
and stats timer necessarily remain active. This measures the widget/panel workload,
not the cost of removing Flutter's engine. Widget-texture examples retain their last
captured image while UI is suspended. No headset FPS improvement is claimed until
measured with the same scene, view, settings, and thermal conditions.

Generated assets have one owner: `example_app` supplies the gallery bundles and
`flutter_scene` supplies engine bundles through their package hooks. The host must
not compile or list another `flutter_scene_generated/` tree; duplicate gallery
owners make startup and model/material lookups ambiguous. Raw asset aliases remain
for the examples' existing `rootBundle` calls.

See [GALLERY_VR_REPORT.md](GALLERY_VR_REPORT.md) for the registry audit, limitations,
build evidence, comparison procedure and headset checklist. For native frame
ownership and local engine prerequisites, see
[DIRECT_SWAPCHAIN_RENDERING.md](DIRECT_SWAPCHAIN_RENDERING.md).

## Steam Frame

The same gallery runs on Valve's Steam Frame, inside its Lepton Android
container. Start **Lepton Development** on the headset so adb has a container to
reach, then run the Frame wrapper around the local-forks helper:

```sh
FRAME_ADB_TARGET=<headset-ip>:5555 ./examples/openxr_quest/tool/frame-build-and-deploy.sh
```

`FRAME_ADB_TARGET` defaults to `frame:5555`; set it to the headset's IP when that
hostname does not resolve. Over USB, adb reaches the native Linux OS instead, so
forward the port first (`adb forward tcp:5555 tcp:5555`) and use `localhost:5555`.
The Frame Controller's face buttons differ from Touch (A/B/X/Y are all on the
right controller, a d-pad on the left); the package README maps each action.

## Augmented Reality

**Augmented Reality** shows Dash in the real room through passthrough. Stick
navigation is off, since the scene must stay pinned to the room. Set **Floor below
head** to where the real floor is: there is no plane detection, and an invisible
shadow catcher at that height puts Dash's shadow on the real floor.

- **Grab** - Aim at Dash (or touch him) and hold grip; he follows the controller.
  While held, that hand's stick pushes him away or pulls him closer.
- **Scale** - While one hand holds him, grip with the other anywhere and move the
  controllers apart or together.
- **Drop and throw** - Released, he falls and bounces on the floor, keeping the
  velocity of the release.
- **Freeze** - The primary button (X/A on Touch; d-pad down/A on the Frame
  Controller) freezes him in the air; press again to let him fall.
- **Controls** - **Distance** and **Size** follow wherever the hands put him, and
  move him from where he is.

Panels stay sharp compositor quads and keep the right depth against Dash: a panel
in front hides him, and he covers a panel he is in front of.

## Resolution and graphics comparisons

At the top of **Settings**, select 50%, 67%, 75%, or 100% of the runtime's
recommended eye dimensions. The labels show actual platform-derived pixel sizes.
Both eye swapchains are recreated between completed frames, without exiting VR,
resetting the camera, rebuilding the Flutter atlas, or clearing the FPS history.
The old pair remains alive until both replacements exist; allocation failure is
reported inline and keeps the previous resolution. Discard the transition sample
when comparing steady-state FPS. The resolution carries across example switches.

The scrollable performance panel reports actual eye render/output dimensions,
runtime-recommended dimensions, relative pixel count, Flutter logical/backing
sizes, atlas dimensions, and the native HUD size. Physical headset panel pixels
are not exposed by OpenXR, so recommended eye size is not labeled hardware size.
The existing native FPS/UI toggle still removes the full Flutter panel chain.

**Low**, **Medium**, **High**, and **Ultra** change shared graphics settings and
resolution together. Manual changes select **Custom**; choosing another preset
does not overwrite that saved settings instance. Custom is kept separately per
example for the current app session, including across tabs and example switches;
it is not persisted across process restarts or transferred between flat and VR.
The authored baseline remains the initial setting for each example.

| Preset | Resolution | Shadows | AO | Reflections | Bloom |
| --- | --- | --- | --- | --- | --- |
| Low | 50% | Off | Off | Off | Off |
| Medium | 75% | 1 × 512 | Off | Off | Off |
| High | 100% | 2 × 1024 | Half resolution, 16 samples | Off | On |
| Ultra | 100% | 4 × 2048 + contact shadows | Full resolution, 24 samples | On, 64 steps | On |

Low/Medium also disable optional GI, god rays, and depth of field. Lighting and
color start from each example's settings defaults. High/Ultra preserve authored
cinematic effects rather than forcing blur/fog onto unrelated examples.

In the web gallery, **FPS** sits beside **Settings**. It reports scene submissions
and Flutter timing separately, plus actual scene target/output sizes, Flutter
backing/logical size, DPR and the OS/browser-reported display size. Web resolution
changes resize scene targets live; UI stays at the platform's backing resolution.
Click the scene to focus; drag (including middle mouse) to orbit the camera target,
use WASD/arrows to move the camera and target, Shift for faster motion, wheel to
zoom toward the pivot, and R to restore the authored camera. In
split-screen examples the shared navigation controls the primary screen view.
