# VeeCut

**The video editor with an AI director.**

Vee watches your footage, plans the cut to your song, then edits whatever you ask. Open source, for Mac, built on Meta's Muse Spark, SAM 3.1, Muse Image and Muse Voice.

- **Vee directs.** Drop in the clips you shot. Vee reads every one with Muse Spark, including what's said, pitches a few videos you could make, reads your song's tempo and drop, and lays out a plan with suggested clips cut to the beat. You keep what you like.
- **Vee edits.** Click a person or thing in the preview, or name it, and SAM 3.1 tracks it through the shot. Then ask in plain words or by voice: make him pop, put sunglasses on the cat, add Vietnamese captions, make it 9:16. Vee picks the tools and does it, one undo step per ask.
- **You stay the editor.** Switch from Simple to Pro for every wheel, curve and keyframe, undo anything Vee did, or bring your own Claude or GPT key.

Built for the Meta Global AI Developer Hackathon (Oct 27 – Nov 4, 2026), Indie Developer track.

> Requires macOS 26 (Tahoe) on Apple Silicon.

## What was built during the hackathon

Everything after the [`hackathon-baseline`](../../tree/hackathon-baseline) tag was built during the event (Oct 27 – Nov 4, 2026). Compare: [`hackathon-baseline...main`](../../compare/hackathon-baseline...main).

### Meta models, wired into the editor
- **SAM 3.1** through the Meta Model API: a Swift port of Meta's SAM mask decoder (bit-identical to the reference, see below), tracked masks saved in the project, effects rendered inside or outside a mask with feathered edges, and frame-exact tracking on just the part of a clip the timeline uses. Transient server errors are retried.
- **Muse Spark** runs Vee's chat with VeeCut's ~60 editing tools, reads every clip (contact sheets plus what's said), pitches video ideas and plans the edit.
- **Muse Image** draws stickers on a flat background, and Apple Vision cuts them out. VeeCut's own mascot art was made with it too (`scripts/vee`).
- **Muse Voice** transcribes captions in any language, Vietnamese included, in batch.

### Vee directs
- **Footage reading and ideas:** drop in a folder; Vee watches it in the background and suggests three videos you could make.
- **Music-first planning:** Vee finds a song's tempo, parts and drop, plans sections to those parts, snaps every cut to a detected beat, keeps the drop inside the cut, and trims the song to the nearest part.
- **Suggested timeline:** the plan shows as ghost clips on the timeline; keep one or Keep All as one undo step. The plan bar shows each section on the timeline's own scale and how full it is.
- **Coaching:** tips with one-click fixes, Vee's short lines over the preview, and Vee Speaks Aloud with hold-Option-Space to talk back.

### Vee edits
- **Canvas objects:** click, brush or name anything in the preview and SAM tracks it through the shot; objects get name tags and can be @-tagged in the chat.
- **Looks:** one-click subject and background looks (Pop Subject, Blur Background, Cinematic, Moody…) and a describe-a-look box powered by Muse Spark; Vee uses the same presets through `apply_look`.
- **Things that follow:** text, labels and Muse Image stickers ride on a tracked object, and never drift more than half off the frame.
- **Smooth Skin:** a face-only retouch that finds the face with SAM.
- **Agent tools:** `track_object`, `apply_look`, `follow_object`, `add_sticker`, `smooth_skin`, `get_plan`, `make_plan`, `edit_plan`, `add_to_section`, each covered by MCP tests.
- **Skills:** the skill library ships inside the app and works offline, and VeeCut adds two of its own: `vee-travel-reel` and `write-vee-skill`, which turns your own routine into a skill.

### The editor around Vee
- Simple and Pro modes, a magnetic timeline, Cmd-scroll zoom, a saved edit history, floating card panels, a new home screen, a pastel design system with shared chip, field and button components, the "Vee is powered by" key manager, and a Vee-narrated onboarding tour.

## Pre-hackathon base (not part of the submission)

- **Palmier Pro.** VeeCut is a fork of [Palmier Pro](https://github.com/palmier-io/palmier-pro) by palmier-io, from its last GPLv3 source release (tag `last-gpl-source`, commit `8805801`). The editor, timeline, effects pipeline, agent panel, and MCP server come from Palmier Pro. VeeCut is not affiliated with or endorsed by Palmier.
- **Environment setup before the event:**
  - `b9be9f2`: resource lookup fix so the app builds and tests pass under Xcode 27 / Swift 6.4.
  - Removal of Palmier-specific docs, release tooling, and this README rewrite.
- **Agent skills.** The skills under `Sources/PalmierPro/Resources/Skills` are copied unmodified from [palmier-io/palmier-skills](https://github.com/palmier-io/palmier-skills) (commit `040e82f`). VeeCut bundles them in the app instead of downloading them.

## Build

```bash
swift build
swift run
swift test
```

Requires Xcode 26 or later with the Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`). Use `swift build --traits BundledSpeech` for on-device speech features.

## MCP server

While the app is open, it exposes an MCP server at `http://127.0.0.1:19789/mcp`:

```bash
claude mcp add --transport http veecut http://127.0.0.1:19789/mcp
```

## License

GPLv3, see [LICENSE](LICENSE). Modified from Palmier Pro since October 2026; see the git history for changes.

Exception: `Sources/PalmierPro/MetaModels/SAMMaskCodec.swift` is a Swift port of Meta's SAM 3.1 mask decoder (meta-sam-parser) and is licensed under the [SAM License](ThirdPartyLicenses/SAM-LICENSE.txt), not GPLv3.

Exception: the files in `Sources/PalmierPro/Resources/Skills` come from palmier-io/palmier-skills and are licensed under the [Apache License 2.0](Sources/PalmierPro/Resources/Skills/LICENSE).
