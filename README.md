# VeeCut

**The friendly AI video editor anyone can use, from first-time creators to pros.**

VeeCut pushes AI as far as it goes to cut out the manual work of editing. Draw on the preview to point at a person, the sky, or a product, and Meta's SAM 3.1 selects it and tracks it through the clip. Then type or say what you want, and Meta's models turn it into color grades, effects, and animated text or stickers. Beginners get a great result in one step. Pros can still fine-tune every edit and undo it.

Built for the Meta Global AI Developer Hackathon (Oct 27 – Nov 4, 2026), Indie Developer track.

> Requires macOS 26 (Tahoe) on Apple Silicon.

## What was built during the hackathon

Everything after the [`hackathon-baseline`](../../tree/hackathon-baseline) tag was built during the event (Oct 27 – Nov 4, 2026). Compare: [`hackathon-baseline...main`](../../compare/hackathon-baseline...main).

_This section is filled in as features land._

## Pre-hackathon base (not part of the submission)

- **Palmier Pro.** VeeCut is a fork of [Palmier Pro](https://github.com/palmier-io/palmier-pro) by palmier-io, from its last GPLv3 source release (tag `last-gpl-source`, commit `8805801`). The editor, timeline, effects pipeline, agent panel, and MCP server come from Palmier Pro. VeeCut is not affiliated with or endorsed by Palmier.
- **Environment setup before the event:**
  - `b9be9f2`: resource lookup fix so the app builds and tests pass under Xcode 27 / Swift 6.4.
  - Removal of Palmier-specific docs, release tooling, and this README rewrite.

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
