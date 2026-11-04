---
name: write-vee-skill
description: Turn the user's own editing routine into a reusable VeeCut skill that Vee follows next time — interview them about the steps, map each step to VeeCut's tools (plan, SAM 3.1 tracking, looks, stickers, captions, reframing), write the SKILL.md and save it with manage_skills. Use when the user asks to make, write, save or teach Vee a skill, a workflow, a recipe or a template ("every Friday I cut a food vlog like this", "remember how I do my intros", "make this my default reel").
---

# Write a Vee skill

A skill is a short playbook Vee loads with `read_skill` when a request matches its description. Good skills are the user's routine in their own words, with each step pointing at the one VeeCut tool that does it.

```
- [ ] 1. Interview — what they make, from what footage, step by step
- [ ] 2. Map each step to a tool (table below)
- [ ] 3. Draft — name, description, checklist, one paragraph per step
- [ ] 4. Show the draft; adjust until they say it's right
- [ ] 5. manage_skills create — then offer to try it on this project
```

**1. Interview.** Ask at most three questions at a time, plainly: what the video is and how long, what footage it starts from, and what they always do to it (order matters). If they've just edited something they like, read it with `get_plan` and `get_timeline` and describe it back as steps instead of asking. Note what changes each time (the song, the person, the sticker) versus what stays fixed (the length, the look, the captions language): the changing parts become **ask** points in the skill.

**2. Map steps to tools.** Use VeeCut's own tools, by intent:

| The user says | Tool |
| :-- | :-- |
| plan it, cut it to my song, sections | `make_plan` (brief, style), then `get_plan`, `add_to_section`, `edit_plan` |
| make them pop, blur or darken the background, a named look | `track_object` → `apply_look` (pop_subject, blur_background, cinematic…) |
| a custom grade on just one thing | `track_object` → `apply_color` / `apply_effect` with `region {maskId, side}` |
| sticker, emoji, hat, sunglasses that follow | `add_sticker` with `maskId` |
| name tag, label, title that follows | `add_texts`, then `follow_object` |
| smooth skin, touch up the face | `smooth_skin` |
| captions, subtitles, in a language | `add_captions` with `language` |
| vertical, 9:16, square, for Reels or TikTok | `set_project_settings` with `aspectRatio` |
| color grade, a look, match shots | `apply_color` (and the color-grading skill) |
| cut silences, remove filler words | `remove_silence`, `remove_words` |
| find a shot by describing it | `search_media` |

If a step has no tool, say so and keep it as a note for the user rather than inventing one.

**3. Draft.** Frontmatter `name` in kebab-case and a `description` that starts with what the skill makes and ends with the phrases the user would actually type ("Use when the user asks for…"). The body: a checklist, then one short paragraph per step naming the tool, the parameters that stay fixed, and **ask** where the user decides. Refer to things by role ("the main person", "the talking clip"), never by ids from this project: ids change in every project, and Vee reads them fresh from tool results.

**4. Show it** in the chat, short, and ask what's missing or wrong. Fix it before saving.

**5. Save.** `manage_skills` with `action: "create"`, the `name`, `description` and the full Markdown as `instructions`. Tell the user the skill's id from the result and that it shows in Settings → Skills, where they can edit or share it. Offer to run it now on this project.

## Keep skills good

- One skill, one kind of video. Split "reels and podcasts" into two.
- Order steps so each builds on the last: plan before placing, edits before reframing.
- Keep fixed numbers only where the user cares (length, blur strength); otherwise let the tool's defaults stand.
- Updating later: `read_skill` first, then `manage_skills` `update` with the full new `instructions`.
