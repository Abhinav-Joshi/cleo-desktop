# Cleo Desktop

A tiny goldendoodle who keeps you company in a corner of your Mac. Click to pet her, play keep-away with a stick, watch her catch a thrown ball, or let her curl up for the evening.

**[Download Cleo 1.0.0 for Mac](https://github.com/Abhinav-Joshi/cleo-desktop/releases/download/v1.0.0/Cleo-1.0.0-macOS-universal-preview.zip)**

Requires macOS 14 or later on an Apple silicon or Intel Mac. No Xcode, ChatGPT, or extra runtime is needed. See the [release page](https://github.com/Abhinav-Joshi/cleo-desktop/releases/tag/v1.0.0) for all download files and release details.

## Install

1. Download and open the ZIP.
2. Drag `Cleo.app` into Applications, then open it.
3. Look for the **paw icon in the menu bar**. Cleo has no Dock icon.

This is an **ad hoc signed preview, not a Developer ID signed, notarized release**. macOS may block its first launch. If you trust the download, attempt to open Cleo, then choose **System Settings → Privacy & Security → Open Anyway**, followed by **Open**. [Apple's instructions](https://support.apple.com/en-us/102445) explain the process.

## Using Cleo

The paw menu controls her size, screen corner, display, sleepy hours, and play. You can hide, pause, snooze, or quit her there. Hover over her while she sits at home for a silent bark and wag; click to pet her. Sleeping Cleo stays curled up and greets a hover with open eyes and a tail wag.

The published **1.0.0 download does not use the microphone or the network**. A build from this source adds hold-to-talk, described under Develop. That build listens only while you hold Cleo, press Control-Option-Space, or choose **Talk to Grok Bot** in the paw menu. It transcribes on this Mac and does not itself send the audio or the transcript anywhere. It still does not request Accessibility, Screen Recording, or Input Monitoring, and it does not start at login automatically.

To remove her, choose **Quit Cleo** from the paw menu, then delete the app.

## Develop

A small native macOS companion inspired by Cleo the goldendoodle, with sharp pixel artwork and animated body, head, tail, and legs. Cleo usually stays near a screen corner, occasionally plays with a ball or carries a stick, and becomes sleepy in the evening. She faces left while resting, with her head and ears anchored during a stationary tail wag. She turns with her direction of travel and faces the pointer during stick play. Click her while she is resting to pet her.

The app uses AppKit, local artwork, and, while you are talking, the microphone and Apple's Speech framework. Speech recognition is requested with on-device recognition required. Cleo does not fall back to Apple's speech servers, and Cleo's process does not open a network connection, account, or telemetry. The transcript is handed to another app on this Mac through a local URL scheme. That other app, Grok Bot, has its own network once you send a message. Cleo does not press send.

Cleo requests only the microphone and speech recognition. It does not request Accessibility, Screen Recording, or Input Monitoring permission. It does not start at login automatically. The app has no Dock icon; its menu bar menu is the control center.

### Build and run

The app requires macOS 14 or later. The default local build targets Apple silicon; the friend download is universal and supports Apple silicon and Intel Macs. Building requires a working Xcode or Command Line Tools installation. The scripts honor an explicit `DEVELOPER_DIR` when it is set. Otherwise they try Command Line Tools, then the developer directory selected by `xcode-select`. They never change the global developer selection.

From this directory:

```sh
./scripts/build.sh
```

The result is `build/Cleo.app`, signed locally with an ad hoc signature. Building does not launch the app. The installed copy lives at `~/Applications/Cleo.app`; open it from Finder when you want Cleo on screen. To update that copy, run:

```sh
./scripts/build.sh --install
```

Installation does not launch Cleo. Any existing `~/Applications/Cleo.app` is moved into `~/Applications/Cleo Backups` before replacement. To remove Cleo, quit it through its menu and delete the app; remove its `local.cleo.companion` preferences separately if you want to reset saved choices.

For a universal friend download, run `./scripts/package.sh`. It builds both native architectures and produces a ZIP, installation instructions, SHA-256 checksum, and metadata under `build/distribution/`, without installing, launching, or publishing anything. Use `./scripts/package.sh --skip-build` to package an already built universal app.

### Controls and behavior

Click the paw in the menu bar, or right-click Cleo, to open her controls:

- **Hide Cleo / Show Cleo**, **Pause / Resume**, and **Snooze for 30 minutes**.
- **Give her a stick**, **Catch a ball**, **Wag hello**, **Curl up and sleep**, and **Back to your corner**.
- **Screen corner**: bottom right, bottom left, top right, or top left.
- **Size**: Small · 128 pt, Medium · 192 pt, or Large · 256 pt. Small is the default; these are sprite sizes, with a little transparent margin around them.
- **Display**: choose among connected screens.
- **Sleepy hours**: choose a start time from 7 pm through 10 pm; sleepy hours end at 7 am. The default is 8 pm to 7 am in your local time.
- **Talk to Grok Bot (⌃⌥Space)** and, while she is listening, **Stop and hand the words to Grok Bot**.
- **Gentle mode · stay put** and **Quit Cleo**.

Hold still on Cleo for a fraction of a second to talk. A short click still pets her, and a stroke still pets her. Release to stop. Control-Option-Space starts and stops the same session from any app. It is a toggle, not a physical hold: watching an arbitrary key for press-and-release needs Input Monitoring, which Cleo does not request. The menu item does the same toggle. Hide, pause, snooze, quit, or another play command cancels listening and does not hand the words off.

While she is listening she stays where she is and loops her existing bark. Reduce Motion and Gentle mode play that bark once and hold the last frame, with her paws and window fixed. When the words are handed off she plays one short bark, then goes back to what she was doing. Nothing is spoken aloud.

Gentle mode and the macOS Reduce Motion setting keep Cleo in place and reduce her animation. With either enabled, stick clicks become petting and ball play becomes a wag instead of a chase. Listening does not walk her around in either mode.

Hover over Cleo while she is sitting idle or wagging at her home spot for two little silent woofs and a tail wag. Her whole head and neck tip her muzzle upward while her body stays fixed. The 16-frame greeting lasts about 0.95 seconds, then she returns to sitting. If she is asleep or sleepy, she stays curled up, opens her eyes, and wags her tail for about 2.4 seconds before resuming her nap. Hovering leaves walking, stick and ball play, petting, bedtime turning, and settling uninterrupted. Move off her visible shape and return to restart a greeting immediately while she is in an eligible mood; holding the pointer over her does not loop it. Greetings also work in Gentle mode and Reduce Motion, with her paws and window staying fixed. There is no audio. Clicking still pets her.

With a stick, Cleo lowers into a playful bow and watches the pointer. Approaching or clicking starts short, springy scoots that keep her roughly 145 points away, within the display's usable bounds. When the pointer moves away she holds her bow. Play lasts about eight seconds; repeated clicks can extend it to twelve seconds before she returns to her corner.

**Catch a ball** plays one 3.8-second sequence: a thrown ball follows a wide arc while Cleo watches, approaches, opens her mouth, pounces to catch it once, lands, and briefly holds it. She then walks home carrying the ball. Ordinary walks have an empty mouth; she carries a stick when returning from stick play.

Before going to sleep, Cleo turns tightly as if following her own tail, then bends her knees and curls down onto her paws. Sixteen turning frames show eight body directions, including front and rear views, while she stays close to her spot. The turn takes about 3.2 seconds and settling takes about 0.9 seconds. Gentle mode and Reduce Motion skip the turn; a sleeping Cleo does not repeat it until she wakes and gets ready for bed again.

Cleo uses a transparent, nonactivating window so interacting with her does not bring another app forward. Only her small visible area accepts clicks; the rest of the desktop remains usable. If any interaction interferes with your foreground app, use the menu to hide, pause, or quit her. No notification or reminder settings are changed.

You can also send a local command to the already running app without changing the foreground app or moving the pointer:

```sh
"$HOME/Applications/Cleo.app/Contents/MacOS/Cleo" --command stick
```

Supported controls are `stick`, `ball`, `wag`, `pet`, `bark`, `sleep`, `home`, `hide`, `show`, `pause`, `resume`, and `quit`. These commands affect only a running Cleo instance; they do not launch the companion if it is closed.

### Talking to Grok Bot

Cleo is the microphone. Grok Bot, bundle id `com.anysphere.sand`, is the agent. The handoff sits behind `AgentProvider`, so another desktop agent can be added later without rewriting listening or the menu. The only provider today is `GrokBotProvider`. A saved `agentProvider` preference selects one when more than one exists.

Grok Bot 0.75.8 registers `grokbot://` and `sand://`. Both accept the same routes. The prompt route is:

```text
grokbot://app/v1/prompt?text=Hello%20there
sand://app/v1/prompt?text=Hello%20there
```

Tested against the installed 0.75.8 app, not guessed from the scheme names:

- The route prefills the main agent's composer. It does not send the message. A draft file on disk gained the probe text, and no sent-message record did.
- `sand://` with a space in the text prefilled the same way (`CLEO HANDOFF SAND 4594`).
- A second link, while that draft was non-empty, did not replace it. Grok Bot keeps the existing draft and only focuses the agent. Cleo cannot see that, so the menu says an existing draft is left as it is.
- A decoded `text` longer than 1000 characters is rejected. The whole URL must be at most 2048 printable ASCII characters, with no fragment, no extra query keys, and no control characters. Cleo collapses newlines to spaces, strips other control characters, shortens the text until the URL fits, and uses `grokbot://`.
- There is no query flag that sends. Cleo does not open `https://cursor.com`.

If Grok Bot is missing, or the link fails to open, Cleo copies the words to the clipboard and activates Grok Bot when it is installed. That replaces whatever was on the clipboard. The menu states that. This is the fallback, not the normal path.

The microphone and speech recognizer run only during a listening session. `requiresOnDeviceRecognition` is set. If on-device recognition cannot run, Cleo stops and does not retry with a server recognizer. The first attempt asks for microphone and speech-recognition permission; those usage strings are in `Info.plist`.

Check the link builder and the listening pose without a microphone or another app:

```sh
./build/Cleo.app/Contents/MacOS/Cleo --self-check
./build/Cleo.app/Contents/MacOS/Cleo --print-grok-url "hello world"
./build/Cleo.app/Contents/MacOS/Cleo --speech-capability
```

### Performance

This implementation avoids browser processes. Its pixel rig animates the body, head, tail, and legs into a fresh complete 64 × 64 frame for each update; copy compositing replaces the entire transparent window buffer without retaining previous poses. Ordinary idle animation updates at 12 frames per second, most active animation at up to 18, ball play and its return walk at up to 24, and sleep about 1.33 times per second. Idle frames are cached after their first cycle. Cleo stops her animation timer while hidden, paused, or the Mac's display/session is asleep. Gentle mode and Reduce Motion further reduce activity. Live focus and transparent-pixel checks have passed; visual tuning is being checked in the actual running app. Being lighter than ChatGPT's pet requires a side-by-side measurement and has not been established.

The incoming ball uses a separate tiny transparent window that shares Cleo's 24 Hz animation timer. It ignores mouse input and cannot take keyboard focus. The ball disappears when caught, hidden, paused, or suspended.

After you choose to run Cleo, find its PID in Activity Monitor or with `pgrep -x Cleo`, then measure an already running instance:

```sh
./scripts/measure.sh 12345
```

The script reads five CPU/RSS samples over eight seconds without opening or launching anything. `ps` CPU is an average and RSS is resident memory, so these are rough operational checks. Compare idle, sleep, and play on the same Mac over a longer period in Activity Monitor before drawing performance conclusions.

### Live validation

Validate the running app directly:

1. Watch the small sprite while she rests. Check that her tail moves while her head and ears remain anchored, with sharp pixels and a left-facing resting pose. Check that earlier poses do not leave trails.
2. Hover over Cleo while she is sitting idle or wagging at her home spot and check for two silent woofs and a tail wag, with her whole head lifting and her body staying fixed. Move off her visible shape and return immediately to restart the greeting. Check that she returns to sitting and does not repeat while the pointer stays still. During walking, stick or ball play, petting, bedtime turning, and settling, check that hovering leaves the activity uninterrupted. Click or gently drag on sitting Cleo and check for the petting hand cursor and small heart.
3. Choose **Give her a stick** with Gentle mode and Reduce Motion off. Approach or click her and check for a low play bow, pointer-facing head, and short springy scoots within the chosen display's usable bounds. Move the pointer away and check that she stops scooting, then returns home when play ends.
4. Choose **Catch a ball**. Check a wide thrown arc, one smooth approach, her mouth opening before the catch and closing around the ball, a landing, a brief hold, and a walk home with the ball attached to her mouth. Check that ordinary walks carry no stick. Then choose **Curl up and sleep** and check that she turns her whole body toward her tail, curls down, and breathes slowly. Hover once she is sleepy or asleep: she should stay curled, open her eyes, wag her tail, and return to her nap without standing or barking.
5. Try **Hide Cleo / Show Cleo**, **Pause / Resume**, and **Snooze for 30 minutes**. Check that hiding removes her from the desktop and pausing stops animation.
6. Keep another app active while you interact with Cleo. Check that it retains keyboard focus and clicks through transparent space reach the desktop or app behind her. If an interaction interferes with your work, hide or quit Cleo.
7. Choose **Quit Cleo** and check that the sprite and paw menu disappear.

Optional diagnostics inspect Cleo's own window and artwork without moving the pointer or sending clicks. Quit an existing instance before this intentional manual launch:

```sh
"$HOME/Applications/Cleo.app/Contents/MacOS/Cleo" --diagnostics /tmp/cleo-diagnostics.json
```

The JSON records whether her window is nonactivating, cannot become key, and stays non-key, plus WindowServer hit checks for transparent and visible sprite pixels. A companion `/tmp/cleo-diagnostics.json.png` contains only Cleo's own rendered view. These diagnostics do not capture the desktop and do not replace checking the live interactions above.

For a Cleo instance started with that `--diagnostics` path, `--command snapshot` refreshes the report and PNG. `--command record` saves a short recording of her own live artwork as `/tmp/cleo-diagnostics.json.gif` and a motion contact sheet as `/tmp/cleo-diagnostics.json-motion.png`. These two diagnostic commands need the launch-time path and never record other windows or the screen.

`--command record-sleep` records six seconds for the complete bedtime sequence. Recordings also save a `-motion.json` file with Cleo's actual window positions and moods, so the circular path can be reviewed without recording the desktop.

`--command record-ball` starts ball play and records six seconds at 24 frames per second, covering the 3.8-second catch and walk home. It composites only Cleo's own sprite and ball into a fixed region of at most 512 × 320 pixels. Its contact sheet samples the throw, approach, open mouth, catch, and return; the motion JSON records the carried toy, ball progress and visibility, and ball/mouth positions. Other recording commands retain their 12-frame-per-second default.

`--command record-bark` previews and records the one-second bark in the running app, using the same diagnostic paths.

`--command record-hover` records three seconds of the appropriate greeting while Cleo is in an eligible sitting or sleeping mood, including her return to resting. It does not move the pointer or synthesize input.

### Source layout

- `Sources/Cleo/App.swift`: native app, menu, hold-to-talk, local controls, and optional diagnostics.
- `Sources/Cleo/Behavior.swift`: moods, timing, bounded movement, and the listening pose.
- `Sources/Cleo/PixelRig.swift`: articulated pixel animation.
- `Sources/Cleo/SpriteView.swift`: frame presentation, transparency, petting, and click-and-hold.
- `Sources/Cleo/SpeechListener.swift`: on-device microphone transcription.
- `Sources/Cleo/TalkHotKey.swift`: Control-Option-Space, without Input Monitoring.
- `Sources/Cleo/AgentProvider.swift`: the provider interface and the Grok Bot link.
- `Sources/Cleo/ThrownBallView.swift`: cached pixel artwork for the noninteractive thrown ball.
- `Resources/`: bundled local pixel artwork and app icon.
- `Artwork/ARTWORK.md`: selected art, generation method, and exact source prompt.
- `Info.plist`: app identity, minimum macOS version, menu bar app configuration, and microphone and speech-recognition usage strings.
- `scripts/`: build and read-only process measurement.
