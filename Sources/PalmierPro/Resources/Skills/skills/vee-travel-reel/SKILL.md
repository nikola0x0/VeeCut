---
name: vee-travel-reel
description: Turn a trip's raw clips into a short travel reel cut to a song in VeeCut — plan the sections to the song with Muse Spark, place the best moments, make the main person pop with SAM 3.1, add a sticker that follows them, caption the talking in its own language, and reframe to 9:16. Use when the user asks for a travel reel, trip recap, holiday vlog, "make a reel from my trip", or a short vertical video of their footage cut to music.
---

# Travel reel

Build the reel in this order. Each step is one ask the user could also have made by hand, so tell them what you did after each one in a short line, and stop to ask only where marked **ask**.

```
- [ ] 1. get_plan — footage read? song chosen? plan already there?
- [ ] 2. make_plan — a reel brief, cut to the song
- [ ] 3. add_to_section — the suggested moments, section by section
- [ ] 4. track_object + apply_look — the main person pops, the background softens
- [ ] 5. add_sticker — one sticker that follows them (ask what)
- [ ] 6. add_captions — the talking clips, in their language
- [ ] 7. set_project_settings — 9:16, last, so every step above is framed once
```

**1. Read the state first.** Call `get_plan`. Use its `footageSummary` and `ideas` to word the brief in the user's terms. If `plan.music` is missing, **ask** which song from the Media panel to cut to; without one, say the cuts won't follow a beat and continue only if they agree. If a plan already exists, **ask** before replacing it: `make_plan` replaces the plan (placed clips stay).

**2. Plan.** `make_plan` with `style: "reel"` and a brief that names the length and feeling, for example "30 second reel of our Da Lat trip, waterfalls and night streets, upbeat". It takes 20–60 seconds once the footage is read. Read the result with `get_plan`: sections follow the song's parts (`pace` calm, rising, peak, fading) and the strongest moment sits on the drop.

**3. Place the moments.** For each section in order, `add_to_section` with the section's first suggested moment (`mediaRef`, `startSeconds`, `endSeconds`), then the next, until `filled` is true. Keep each moment as suggested: the plan already trimmed them to the beat. Never place a moment twice.

**4. Make the main person pop.** Pick the placed clip where the person is largest and moving (the peak section is a good bet). `track_object` with `object` naming them as they look ("man in black jacket", "woman with yellow bag"), not "person" when several people are in frame. Then, with the returned `maskId`, two `apply_look` calls on that clip: `look: "pop_subject"`, then `look: "blur_background"`. These are VeeCut's tuned presets; don't hand-pick color numbers, which can over-saturate a cool shadow into blue.

Tracking takes 10–90 seconds depending on the clip's length; say so before starting.

**5. One sticker.** **Ask** what it should be, offering one idea that fits the footage ("pink heart sunglasses", "tiny crown"). `add_sticker` with that `description` and the same `maskId` so it rides on the person. One sticker per reel: more reads as clutter.

**6. Captions.** If any placed clip has someone talking, `add_captions` with `language` set to what they speak ("vi" for Vietnamese, "en" for English). Leave style, animation and transform out so the captions use VeeCut's clean default.

**7. Reframe last.** `set_project_settings` with `aspectRatio: "9:16"`. Clips re-fit automatically; the tracked look and the sticker follow.

## Finish

Tell the user in one or two lines what the reel now has (length, sections, the pop, the sticker, captions) and that each step is its own undo. Offer one next step, such as a title at the start with `add_texts`.

## Don'ts

- Don't place clips before a plan exists, and don't re-run `make_plan` to tweak one section: use `edit_plan`.
- Don't track with a vague noun when two similar things are in frame ("cat" may find the dog). Name a visible detail, or ask the user to click the object so you get its tag.
- Don't reframe before the edits; do it once at the end.
