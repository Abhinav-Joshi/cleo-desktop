# Cleo artwork

The selected artwork is the **first pixel-art version**, chosen by the user. `cleo-pixel-source.png` preserves that source sheet; `cleo-pixel-source-v2.png` is an unused flat-color exploration. The original smooth 3D exploration is not part of the app.

Created with the built-in image generator using Cleo's provided `IMG_0200.JPG`, `PHOTO-2026-08-17-20-13-24.jpg`, and `PHOTO-2026-02-17-13-10-26.jpg` as identity references. No API key or CLI image-generation fallback was used.

`scripts/prepare-art.swift` slices the sheet to sixteen local 64×64 PNGs in `Resources/`, uses nearest-neighbor sampling, and makes alpha binary for sharp edges. The runtime uses a stable selected pose for each action and continuously deforms that complete image around measured neck, tail, and leg joints through `PixelRig.swift`. Joint influence fades into the torso so there are no separate cutout parts to detach. It does not cycle through the sixteen independent source drawings as a slideshow. The pixel rig adds the moving stick, ball, and affection heart. Every frame starts on an empty transparent canvas and replaces the window buffer with copy compositing to prevent trails.

Regenerate runtime resources from the selected source, from the project directory:

```sh
xcrun swift scripts/prepare-art.swift Artwork/cleo-pixel-source.png Resources
/usr/bin/iconutil -c icns Artwork/Cleo.iconset -o Resources/Cleo.icns
./scripts/build.sh --install
```

The final selected image-generation prompt was:

> Use case: stylized-concept. Production asset: PIXEL ART desktop pet sprite sheet. User wants distinctly MORE PIXELATED: authentic hand-pixeled cozy retro game sprites, clear big square pixels, limited palette about 12 colors, warm dark-brown 1-pixel outline, simplified clustered cream curls, apricot floppy ears, dark round eyes, fluffy wagging tail, tiny brown collar and gold tag. Subject Cleo: same cream/apricot goldendoodle in the photos, recognizable real dog's identity. No smooth painting, no 3D rendering, no antialiasing, no gradients, no realistic hair, no text, no numbers. Treat each frame as a 64x64 pixel videogame sprite, enlarged by an integer scale with NEAREST NEIGHBOR hard square pixel edges. Exactly FOUR columns and FOUR rows, sixteen sprite cells on a square truly TRANSPARENT background. Each cell contains one full-body Cleo and accessories only. Identical dog design, color palette, scale and left-facing three-quarter camera across all16. 8 logical-pixel empty transparent padding every side of each cell; paws on constant baseline near bottom. Sheet row1 four animation frames of sitting happily wagging tail left-middle-right-middle, third frame blink. Row2 four sequential trotting-with-stick gait frames, little brown stick held horizontally in mouth, left facing, legs alternating, fluffy tail behind. Row3 four frames of catching small red ball: crouch with approaching ball, little hop with ball near nose, catch ball in mouth, land holding ball. Row4 four subtle sleeping breathing frames, curled up lying down, head on front paws, eyes closed. Same scale across poses; sleeping width same as standing dog width. Absolutely NO rendered grid or dividers, no shadows, no scenery, no floor, no extra characters, no decorative icons. 16 clean isolated pixel sprites, actual alpha transparency in all empty areas. Pixel art charm, slightly silly, irresistibly cute but not giant-headed. Prioritize crisp big pixels and exact regular 4x4 layout.

## Bedtime turning animation

`cleo-bedtime-turn-source.png` was generated with the same built-in image tool, using `cleo-pixel-source.png` as the style and identity reference. `scripts/prepare-turn.swift` saves sixteen sharp 64×64 turn frames in `Resources/turn-00.png` through `turn-15.png`, with aligned feet and transparent margins. `PixelRig.swift` orders matching views and their native mirrors into eight body headings with two steps each. This is a dedicated turning animation, including front and rear views; the window only moves in a subtle 8×5-point loop.

The bedtime image-generation prompt was:

> Use case: stylized-concept. Production videogame ANIMATION SPRITE SHEET. Reference is Cleo's approved pixel-art identity and exact aesthetic. Match THAT fluffy cream/apricot goldendoodle, soft rounded pixel clusters, dark eyes/nose, floppy apricot ears and feathery tail, brown collar and small gold tag. Preserve her approved proportions and colors. TASK: a COHERENT sixteen-consecutive-frame FULL 360-DEGREE TURNING animation of Cleo walking in a TIGHT CIRCLE ALMOST CHASING HER OWN TAIL before bed. Her whole spine is curled into a rounded C-shape, head turns back toward her raised feathery tail, nose following tail, inner paws making short circular steps, outer paws stepping around. This must unmistakably look like a dog circling its own tail, with whole-body rotation showing FRONT, SIDE, BACK, and the opposite SIDE. Not walking a straight line. No jumping. Her paws keep contacting the floor plane. Camera stays fixed at slightly elevated cozy desktop-pet three-quarter perspective; DOG turns through 360degrees, camera never turns. SHEET: EXACT4x4 equal grid, 16 chronological frames left-to-right then top-to-bottom, one isolated full dog per cell, canvas square with ACTUAL alpha transparency, no drawn grid. Keep identical scale, floor baseline and center of turning in each cell, with at least6 logical pixels of transparent margin on all four sides. Design each as a crisp64x64 logical pixel sprite with intentional square pixels, nearest-neighbor appearance, never blurred or antialiased. Sequence starts LEFT-facing (matching reference). Frames1–4 gradually rotate from left profile toward front-facing; frames5–8 rotate front-facing through right profile; frames9–12 rotate right profile toward REAR-facing (back of head, tail root, hindquarters visible); frames13–16 rotate REAR-facing around back to the initial LEFT-facing angle. Each frame advances about22.5degrees with a sequential paw step. While rotating her head follows her own tail so neck and body stay curved, front paws slightly crouched in preparation to sleep. Tail must remain anatomically ATTACHED to her rump and wag subtly. No teleporting body parts, no stationary detached fur, no overlapping extra dog, no duplicated tails. One same coherent character throughout. All sixteen frames depict this single turning sequence, NOT a collection of different sitting/ball/stick poses. No ball, stick, toy, bed, ground, shadow, hearts, sparkles, labels, letters, numbers, words, borders, or scenery. Final frame near-start facing left with head low, ready to curl down. Match reference pixel-art style and warm cream curls exactly. Deliver one clean transparent square4x4 sprite sheet of sixteen progressive turning frames.

## Hover bark animation

`cleo-bark-source.png` is a dedicated 4×4 sheet generated with the built-in image generator. `Resources/cleo-00.png` supplied the exact approved seated character, and `cleo-pixel-source.png` supplied the original identity and style reference. The complete prompt is preserved verbatim in `cleo-bark-prompt.txt`. No API key or CLI image-generation fallback was used.

The generated sequence lifts the complete head and neck so the nose, upper muzzle, eyes, and ears tip upward together during two woofs. The mouth closes between them, and a tiny tongue appears only inside the open mouth. The runtime uses sixteen prepared bark textures over 0.95 seconds while the pixel rig adds a tail wag. The body remains fixed; the tail mask excludes the generated head and ear pixels. These dedicated head drawings replace the earlier mouth deformation; the bark does not draw a moving lip patch in code. There is no audio.

Hover starts this bark only from the seated `idle` or `wag` mood at Cleo's home spot. Walking, stick play, running, ball play, petting, bedtime turning, and settling remain uninterrupted by hover. After the greeting she returns to her seated rest.

From the project directory, prepare the runtime resources with:

```sh
xcrun swift scripts/prepare-bark.swift Artwork/cleo-bark-source.png Resources/cleo-00.png Resources
./scripts/build.sh --install
```

`prepare-bark.swift` produces `Resources/bark-00.png` through `bark-15.png` and a review sheet at `Artwork/cleo-bark-frames.png`. It samples each cell with nearest-neighbor scaling to 64×64, makes alpha binary, and registers the generated head by the connected gold collar-tag component. The prepared textures keep the approved seated body, paws, collar, and tail pixels unchanged while replacing the complete head and neck above their fur join. At runtime only the masked tail receives the wag deformation. Only the largest connected generated head region is retained during preparation, which removes disconnected tail-tip fragments.

The source's final row drifts in scale, so the processor uses this zero-based source order rather than all sixteen drawings in order:

```text
[-1, 0, 2, 3, 4, 5, 6, 0, 8, 9, 10, 11, 6, 0, 0, -1]
```

`-1` means the original approved seated frame. This bookends the greeting with the exact idle texture and reuses stable relaxed head drawings for the ending. Keep the registration and curated ordering when regenerating from the existing sheet; review the contact sheet and actual running hover animation after changing either source or processor.

## Curled sleeping greeting

Hovering during sleep or the sleepy mood uses a separate `sleepGreeting` state lasting 2.4 seconds. It retains the exact existing curled sleeping texture, reveals rounded open eyes procedurally, and animates only the masked tail. It never switches to the seated bark pose, stands up, or plays audio. No additional image generation or artwork assets are used for this greeting.

The behavior resumes the nap afterward. Bedtime turning and settling do not accept hover greetings. Each fresh hover entry restarts the appropriate greeting without a cooldown while Cleo is in an eligible seated or sleeping mood; a stationary pointer does not repeat it.

## Ball sequence and carried toys

Ball play reuses the existing neutral `bedtimeWalking` body for the whole catch and return walk. Approved bark head poses are composited onto that walking body once at initialization, providing one coherent mouth opening from about 1.1 to 1.5 seconds, contact at 1.6 seconds, and closing from 1.7 to 1.85 seconds. The source body and camera stay consistent; no new image generation or artwork assets are needed. A normal walk also uses the neutral texture. The original walking-with-stick texture is selected only when `CarriedToy.stick` is actually carried, including a return from stick play.

`BallTimeline` in `Behavior.swift` defines one 3.8-second action. Cleo watches until 0.35 seconds, approaches smoothly from 0.35 to 1.2 seconds, catches once at 1.6 seconds, and finishes landing by 2.2 seconds. She holds the caught ball for the remaining time and then walks home with `CarriedToy.ball`. Ball progress is normalized from zero to one and remains one during the return. The sequence does not use a repeating jump or ball-path loop.

The incoming ball is a separate tiny transparent, nonactivating `PetPanel` containing `ThrownBallView`. It ignores mouse events and shares the existing 24 Hz timer; it has no timer of its own. A global quadratic Bézier starts up to 220 points to the side, uses a control point raised by up to 150 points, and ends at the currently rendered muzzle. Its start, control, and center are clamped inside the selected display's visible frame with room for the ball. Top corners naturally flatten the available arc. Ball size and positions follow the chosen sprite size and backing scale.

`SpriteView` converts the renderer's 64-pixel, top-left mouth coordinate through the current mirroring and window position. `PixelRig` draws no incoming local ball. At the catch, the separate panel hides and the ball becomes part of the source texture at the selected head's mouth anchor before joint deformation, so it follows the head throughout the hold and return. The seated rest clears the carried toy. Hide, pause, snooze, suspension, other activities, and quitting also hide the separate ball. Stick play continues using its existing play-bow texture and motion.

The ball sequence and ball-carry return use a 24 Hz timer; their panel positions snap to backing pixels for smoother motion on Retina displays. The renderer's change key includes the precise animation time, carried toy, and ball progress rather than imposing another 18 Hz limit. Existing idle, stick, and other animation cadences remain unchanged.

For live visual review, `--command record-ball` starts the action and captures 144 frames at 24 frames per second. A fixed world-space region includes the two sprites and flight path, scaled to at most 512 × 320 pixels. The recording composites only Cleo's own sprite snapshot and cached ball image, without reading any screen buffer or other window. Its six-frame contact sheet uses capture indices `0, 20, 36, 40, 100, 142`, covering throw, approach, open mouth, catch, and return. The accompanying motion JSON includes `carriedToy`, `ballProgress`, timer interval, `ballVisible`, `ballX`, `ballY`, `mouthX`, and `mouthY`. The actual running app remains the reference for smoothness because GIF viewers may quantize frame delays.
