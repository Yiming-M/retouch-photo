---
name: retouch-photo
description: Interactively retouch existing photographs on macOS, including supported camera RAW and Live Photo stills. Extract detailed visual elements, search online for closely matched photographic references, agree on styles and protected regions, then combine code adjustments and imagegen where appropriate. Preserve editable working materials.
---

# Retouch Photo

Turn a supplied photograph into user-approved versions. Respond in the user's
language and follow the five stages below. If the user requests only visual
extraction, references or plans, stop at that stage; do not execute a retouch.

For a group, handle each photo as its own interactive job. A reply such as "three
versions each" sets the count, not approval to edit the group. Normally take the
current photo through analysis, references, plans and confirmation before editing
it. If the user explicitly approves several photos' plans and requests continuous
execution, finish them sequentially and deliver as requested without asking again.
Carry shared preferences forward, while keeping each photo's scope and style clear.

## 1. Receive the image and optional direction

The user supplies the target image and may describe a desired look, areas to focus
on, objects to remove or details to preserve. Distinguish targets from references.
Do not require a detailed brief before looking at the image. Record the requested
number of plans or versions when given. Ask about intended use only when it affects
framing or output choices.

Preserve the source and inspect its actual format, orientation, dimensions and
decoding support. Use macOS system tools to prepare viewable RAW/HEIC previews and
keep the full-resolution source for editing. A filename extension alone does not
prove RAW support or that a HEIC is a Live Photo. If a Live Photo is supplied, keep
its original still/video pair and pairing metadata when available; state whether
the requested work covers only its still or also its motion component.

Read [native-processing.md](references/native-processing.md) when decoding,
adjusting pixels, building masks or compositing. The bundled helper uses Core Image,
Image I/O and optionally Vision; code adjustments do not require manually operating
an editor. Report actual decoding failures without substituting a thumbnail as the
full-resolution RAW.

## 2. Extract detailed visual elements

View the image and inspect relevant details at larger scale. Produce a concrete
inventory that can drive both reference searches and local editing:

- **Identify objects specifically.** Use landmarks, readable signs, architecture,
  clothing, fur and other distinguishing evidence. Identify a travel landmark or
  a pet's likely breed when supported, rather than stopping at "a building" or
  "an animal." Give evidence and qualified candidates when uncertain; verify
  online when useful, without inventing an exact identity or location.
- **Extract visible text and logos.** Transcribe readable lettering as it appears.
  Record its position, orientation, associated object and any obstruction. Use
  OCR when helpful and check its readings against the image. Mark partly readable
  or uncertain text and record when there is no visible text.
- **Describe every salient object.** Record its frame location, orientation and
  posture or action, even for a single subject. Add details such as material, size
  and visible extent where they help identify the object, find a reference or plan
  the edit. Group incidental objects when their individual differences do not matter.
- **Describe relationships.** Record relative placement, overlap and interactions.
  Include details such as distance, contact, gaze, held objects, reflections or
  shadows where they matter to the scene. For a single subject, describe its
  relationship to the environment and frame boundaries.
- **Record visual conditions.** Describe composition and perspective, light source
  and direction, bright/dark areas, color relationships, texture, noise and blur.
  Distinguish observed conditions from aesthetic judgments: darkness is not
  automatically a defect in a night scene.

Keep this stage descriptive. Editing goals belong in stage 4. Reuse these elements
explicitly in the search keywords and in each proposed regional adjustment.

## 3. Search online for photographic references

Always perform online research for a new reference-selection stage. Build queries
from stage 2's specific subject, pose/relationships, setting, composition, lighting
and colors. Use extracted lettering when it helps identify the subject or setting.
Partial matches are acceptable: relax less important terms while retaining the
elements that determine the photograph's appearance.

Read [reference-search.md](references/reference-search.md) for source selection,
quality screening and browser fallback. Search photographic works first, including
international competition winners, established photographers and creator/community
platforms such as Instagram, Unsplash and Flickr. Strong, visibly well-received
work is eligible even when the photographer is not famous. Inspect the actual
images, not just search snippets or reputation. Try the built-in browser with any
existing login for the strongest inaccessible candidates. Use accessible sources
for lower-priority matches.
Use reliable photography textbooks or professional tutorials when suitable image
references cannot be retrieved; be explicit about that fallback.

For **N requested plans, present N distinct reference photographs**, one per plan:
each should be among the closest visual matches found, with meaningfully different
styles. If the user specified one style, keep alternatives within that direction.
If the count or edit permissions are still open, shortlist candidates here and
finalize the selection after the questions in stage 4.
Show each reference with its photographer/source link, matched elements, important
mismatches and what can be borrowed. A gallery link or several names is not a
substitute for selecting photographs. Do not invent extra matches to meet a count.

## 4. Propose plans and confirm the scope

Before drafting plans, ask the user about any of these choices they have yet to make.

- Whether to protect lettering and logos actually found in stage 2. Inspect the
  relevant areas at sufficient resolution first, then point out what was found
  when asking. If none are found, record that observation and skip this question;
  do not ask hypothetical questions about text or logos that might be discovered.
- Whether to allow a small crop.
- Whether to allow extending the canvas.
- Whether to allow `$imagegen` for the retouch, including local reconstruction or a
  generated lighting/color guide.

Group the outstanding questions in one exchange. Ask for the plan count here if it
is still unspecified. Reuse explicit answers already given and wait for any missing
answers before drafting. Treat cropping, extending the canvas and imagegen as
separate permissions. Use imagegen for an extension only if both are allowed.

Within those choices, draft the requested number of distinct plans for the current
photo, adapting one selected reference to each plan. Disclose any shortfall in
reference photographs and identify any tutorial guidance used in their place.
For each plan, state the following.

- **Appearance:** the intended result and how it adapts the reference; explicitly
  state color versus monochrome. Preserve the source's color mode unless the user
  requests or approves a conversion; a monochrome reference alone does not decide it.
- **Composition:** whether to keep, crop, straighten or outpaint; identify the
  framing, aspect ratio and any content entering or leaving the frame. Avoid
  clipping landmark tops, important text, hands or held objects unintentionally.
- **Regional edits:** what changes on each identified subject or area, including
  the exact objects to remove or retain. For removal, account for attached items,
  shadows, reflections and newly exposed background where relevant. Removing a
  crowd does not by itself authorize removing fixed architecture or barriers.
- **Protection and transitions:** which content/structure is preserved, which
  light/color adjustments remain allowed there, and where overlap may be blended.
  By default, "unchanged" means preserve identity, shape, text and placement while
  allowing agreed light/color changes; honor pixel-identical requirements separately.
  If text protection is requested, mark the relevant zones. When a generative
  pass overlaps them, specify how the original lettering will be put back.
- **Implementation and output:** intended code adjustments, imagegen regions or
  conditional use, plus format, dimensions, output color space and bit depth. The
  native helper defaults to sRGB and 8-bit output. Let the expected visual result
  determine the method, with a concrete inspection criterion if the choice is
  conditional. Do not treat avoiding or maximizing imagegen as a goal.

Show a schematic region annotation with a legend when local edits, retention or
reframing are involved. Identify and draw the regions yourself. Ask the user to
confirm the plans and annotated scope together before refining compositing masks
or executing the retouch.
Do not repeat confirmation already provided for that plan. A request to regenerate
plans returns here, not to rendering; retrieve new references if the direction changes.

## 5. Execute, inspect and deliver

Execute only the approved photos and versions, one photo at a time. Resolve routine
parameter and mask choices within that scope; obtain a revised agreement only for
a material change to the look, content or protected details.

### Choose and combine methods by the result

Use reproducible code for suitable exposure/white-balance adjustments, tone and
color, denoising, sharpening, local healing, masks, cropping and blending. Develop
RAW at full resolution, applying exposure/white balance there when appropriate;
do not flatten it to a small JPEG as the source of the final edit.

If the user allowed `$imagegen`, use it for approved reconstruction, removal,
outpainting or appearance adjustments when it offers the needed result. Code need
not fail first when the task clearly calls for generated content. When code
adjustments fall short, consider imagegen for the relevant region within the agreed
scope. Read its skill and use the built-in tool by default; missing access does not
authorize silently switching to a paid API/CLI.

Keep protected source content separately available as crops/layers and masks.
Generate with enough surrounding context, then use code to composite only the
authorized content onto the original-derived canvas. A full-frame generated
background plate is not permission to replace a protected person with its generated
likeness. Feather/blend overlapping transition regions after matching registration,
perspective, light, color and texture. Refine automatic masks around hair, neck,
fingers, phones, gaps and transparent objects; segmentation is only a starting point.
Avoid alignment warps that bend architecture or railings to disguise a mismatch.

When protecting text during generation, use the stage 2 inventory to save
original-resolution crops with the lettering, placement coordinates and enough
surrounding context to blend. Apply generated reconstruction or lighting to the
intended areas, then composite the source lettering or sign panels back with local
masks. Feather at the surrounding material, outside the glyphs. Match perspective
and allowed light/color changes without redrawing characters or replacing source
lettering with OCR output.

For appearance-only work, a generated light/color guide may be applied to the
original detail instead of replacing texture. Record that distinction. Branch
versions from the source or an accepted working stage, and preserve color
intermediates before optional monochrome conversion.

### Inspect and refine

View the whole result and relevant close-ups against the original and approved
reference/plan. Check the intended look as well as protected details, object
removal remnants, geometry, clipping, seams/halos, lighting and texture. For skin,
check the agreed level of blemish repair while preserving identity, expression,
pores and normal lip texture. Do not infer pixel preservation from a plausible
preview: check the protected region numerically when that is a requirement, and
state whether the check precedes an approved global adjustment.

For protected text, compare the lettering crops at full size. Check characters,
logos, stroke shape, position and seams; treat OCR agreement as a secondary check.

Repair the specific parameter, mask or patch while retaining accepted work. If a
generative region still violates a protected invariant after two targeted repair
attempts, stop regenerating it and explain the limitation or propose a narrower
edit. Verify dimensions and format; distinguish enlarged generated detail from
information recovered from the camera source.

### Deliver and retain editable material

Show each finished version and an original/result comparison with clear labels;
for revisions, also compare the previous version when useful. Provide absolute
file links, explain where code and imagegen were actually used, and identify any
unmet requirements. For a group, deliver per photo or together as the user requested.

Keep one working folder per source with its original/stable source reference,
visual inventory, selected references, approved plan/annotation, versioned recipes,
masks, accepted generated patches/prompts, final outputs and necessary replay code.
Keep the final versions distinguishable from trials. Preserve originals and prior
accepted results; remove only disposable trials that no accepted recipe references.
Read [working materials and replay](references/native-processing.md#working-materials-and-replay)
for the native helper's conventions.

For RAW, retain the original RAW plus replayable adjustments and a viewable raster
result; do not claim that edits are baked into sensor RAW, that JSON is an Adobe
XMP preset, or that flattened DNG preserves sensor data. For Live Photos, retain
the original pair and identify a retouched still as a still unless an edited,
working Live Photo pair was actually produced. For ordinary images, preserve
format and resolution where practical, and explain changes needed for the agreed
crop, outpaint or output. When revising, load the accepted working materials and
change only the requested photos/areas; do not restart unrelated edits.
