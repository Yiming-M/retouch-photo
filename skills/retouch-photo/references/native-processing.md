# Native processing on macOS

Use the helper for repeated decoding, parameter adjustment, masks and compositing.
The helper compiles on invocation. It requires Xcode or Command Line Tools 15+,
Swift 5.9+, and the macOS 14 SDK or later. The minimum host is macOS 13.5 with
Xcode or Command Line Tools 15. Check the host requirements of newer toolchains.
Automatic foreground masks need macOS 14+ at runtime and a working Vision model.
The helper was tested on macOS 27.0.1 with Swift 6.4.
There are no Python packages, paid editor dependencies or GUI actions in this route.
If the toolchain/decoder is unavailable, report that specific limitation. Do not
install software or switch to a paid API merely because a native command failed.

Execution note: Core Image rendering can fail in the Codex filesystem sandbox even
when Image I/O can decode the file; forcing CPU rendering did not resolve that on
the development host. If this occurs, use the tool's normal approval mechanism to
retry the same image operation outside the sandbox. Do not classify the source as
unsupported based on that failure alone, and do not modify security settings.

Run the installed or repository copy with its actual absolute path:

```bash
sh /path/to/retouch-photo/scripts/photo.sh --help
sh /path/to/retouch-photo/scripts/photo.sh inspect /path/to/photo.CR3
sh /path/to/retouch-photo/scripts/photo.sh render /path/to/recipe.json
```

The wrapper keeps Swift's module cache under the OS temporary directory. All paths
inside a JSON specification resolve relative to that JSON file, not the shell's
current directory. An existing output is rejected; revise the output filename for
each new render. The script never writes into the source image.

## Inspect and prepare an analysis image

`inspect` reports the Image I/O type, RAW classification, stored and oriented
dimensions, bit depth and profile. For RAW it also reports the decoder version and
effective settings. A small render checks decoding, but does not establish that a
full-resolution render or every camera compression variant will succeed.

Create a minimal render recipe to decode an input for viewing:

```json
{
  "version": 1,
  "source": "source/original.CR3",
  "output": "analysis/preview.png"
}
```

View that output before judging the photo. This uses native oriented dimensions;
if a smaller analysis copy is useful, resize a separate copy using `sips`, and map
any coordinates back to the full-size canvas. Do not use the reduced copy as the
final source. RAW loading uses `CIRAWFilter` at full scale, not its embedded preview.
Ordinary images use their embedded profile and EXIF orientation through Image I/O.

## Render recipe

Only `version`, `source` and `output` are required. Optional fields are `raw`,
`filters`, `layers`, `crop`, `color_space`, `bit_depth` and `jpeg_quality`.

```json
{
  "version": 1,
  "source": "../../source/original.CR3",
  "output": "final-v1.tiff",
  "raw": {
    "exposure": 0.35,
    "neutralTemperature": 5300,
    "neutralTint": 3
  },
  "filters": [
    {"name": "CIVibrance", "params": {"inputAmount": 0.12}}
  ],
  "layers": [
    {
      "mask": "../../masks/background.png",
      "protect": "../../masks/subject.png",
      "filters": [
        {"name": "CIExposureAdjust", "params": {"inputEV": -0.2}}
      ]
    }
  ],
  "color_space": "srgb",
  "bit_depth": 16
}
```

These numbers illustrate syntax, not a recommended photographic preset. Choose
values from the photo and agreed look. Use a different recipe per version.

Processing order is: decode/orient source with RAW settings where applicable →
global filters → local layers in listed order → optional final crop → color-managed
export. The working pipeline uses extended linear sRGB and half-float pixels.

RAW settings are optional; omitted settings retain the system decoder defaults:

| Key | Meaning / allowed values |
| --- | --- |
| `exposure` | RAW exposure adjustment |
| `neutralTemperature` | White-balance temperature, 2000–50000 K |
| `neutralTint` | White-balance tint, −150–150 |
| `boostAmount` | Global tone-curve amount, 0–1 |
| `boostShadowAmount` | Shadow boost, 0–2 |
| `luminanceNoiseReductionAmount`, `colorNoiseReductionAmount` | Denoising, 0–1, if supported by this decoder/image |
| `sharpnessAmount`, `contrastAmount`, `localToneMapAmount` | Decoder adjustments, 0–1, if supported |
| `decoderVersion` | Exact supported version string reported by the system |

Do not apply `raw` settings to JPEG/PNG/HEIC input. For raster exposure use
`CIExposureAdjust` with `inputEV`; for saturation/contrast use `CIColorControls`.
`filters` accepts installed single-image Core Image filters with number/boolean or
numeric-vector parameters. Each filter can sample extended edge pixels and its
result is cropped back to the input canvas. For example `CIToneCurve` uses
`inputPoint0` through `inputPoint4`, each a two-number vector. Unsupported filters
and parameters produce an error. Use this route for photometric operations, not geometry
changes that invalidate the approved masks. For other operations, add only the
job-specific code needed, then retain it with the working materials.

Omit optional string fields (`color_space`, layer `image`, and layer or overlay
`protect`) to use their defaults. When present they must be nonempty strings.
`color_space` is `srgb` (default) or `display-p3`. `bit_depth` is 8 (default) or 16.
PNG and TIFF support both; JPEG requires 8, with `jpeg_quality` in 0–1 (default 0.95).
For a RAW-derived working/master raster, prefer 16-bit TIFF when appropriate to the
agreed delivery. Increasing a generated 8-bit image's storage depth does not restore
RAW information. Do not promise preservation of all source EXIF metadata in exports.
This helper exports SDR images, not HDR gain-map files or arbitrary source ICC spaces.

## Masks and region annotations

Masks are opaque grayscale PNG files: black = excluded, white = included,
intermediate values = blend coverage. Alpha is not the selection channel. Use the
oriented, uncropped source dimensions for every mask. Coordinates everywhere in
the specs use pixels measured from the **top-left** of that image, with y downward.

Generate an initial foreground selection with Vision when useful:

```json
{"source": "../source/photo.heic", "output": "subject.png"}
```

```bash
sh /path/to/retouch-photo/scripts/photo.sh foreground masks/foreground.json
```

The command reports available instance IDs. To select particular detected instances,
add `"instances": [1]` with actual reported IDs; absent this key, all foreground
instances are selected. A detected foreground is not automatically the user's
protected region. Inspect hair, held objects, transparency and holes. Detection may
fail; make/refine a polygon mask instead of accepting an empty or incorrect result.

For polygon selections, `mask` fills polygons in order on a black canvas. Set a
later polygon's `value` to 0 to cut a hole. `invert` and `feather` are optional.
Feather is a Gaussian radius in full-resolution pixels, not a percentage.

```json
{
  "width": 1600,
  "height": 1000,
  "polygons": [
    {"points": [[400, 100], [850, 100], [950, 950], [300, 950]], "value": 1}
  ],
  "feather": 3,
  "output": "subject-soft.png"
}
```

```bash
sh /path/to/retouch-photo/scripts/photo.sh mask masks/subject.json
```

Use a hard, fully white mask for a core region that must receive none of a particular
layer. A soft protection mask attenuates that layer; it does not entirely block it.
The effective edit mask is `edit × (1 − protect)`. Set feathering before this final
exclusion so blur cannot reintroduce the layer inside a fully protected core.
Each layer or overlay accepts one `protect` mask. Merge multiple protected regions
into one full-canvas mask first.
Maintain transition coverage where blending is authorized, not over locked details.

Use a schematic overlay to review the plan. Refine compositing masks after the user
confirms the scope. To check actual coverage after editing, generate an overlay
from the masks used in compositing.

```json
{
  "source": "source/photo.jpg",
  "mask": "masks/edit.png",
  "protect": "masks/protected.png",
  "output": "analysis/regions.png",
  "opacity": 0.4
}
```

```bash
sh /path/to/retouch-photo/scripts/photo.sh overlay regions.json
```

Show the image with its legend: green = protected, red = editable, yellow = partial
coverage/transition. This is a review aid, not an automatic semantic proof. A full
white edit mask can be created with a full-canvas polygon. A background mask can be
created as its complement through the `protect` field; no second segmentation is
needed. Global filters and RAW settings are still applied to protected regions when
approved. If global changes are forbidden there, move those changes into masked
layers rather than relying on `protect` to reverse earlier operations.

## Generated patches and local compositing

Use `$imagegen` for the actual generation. Save the accepted image locally before
referencing it in the recipe. For a full-canvas image with matching dimensions:

```json
{
  "image": "generated/accepted.png",
  "mask": "masks/edit.png",
  "protect": "masks/subject.png"
}
```

Insert this object into `layers`. For a cropped patch, add an explicit
`"rect": [x, y, width, height]` in source-canvas coordinates. This maps the patch to
that region, requiring nearly identical aspect ratios. It rejects silent full-frame
resizing and large anisotropic distortion. If the generated asset has drifted in
perspective, framing or subject geometry, align/regenerate it before compositing.
Rectangle placement is not automatic image registration. A patch can have its own
`filters` for color/light matching before blending. All masks remain full-canvas.

Without `image`, a layer applies its filters to the current canvas and blends that
adjusted candidate through its mask. With `image`, the accepted patch is placed on
the current canvas and blended through the same mechanism. Outside the mask the
current canvas is retained. A `crop` on the overall recipe uses `[x,y,width,height]`
and runs last; include it only in the approved plan.

## Working materials and replay

Use a small per-photo directory, for example:

```text
photo-job/
  source/                 original or source reference
  plan.md                 approved plans, invariants, references and confirmation
  analysis/               analysis preview and region annotation
  masks/                  masks and their generation specs
  versions/warm-v1/
    recipe.json           exact ordered processing instructions
    generated/            accepted assets and exact imagegen prompts, if any
    final-v1.tiff         delivered image
    final-v1.tiff.render.json
```

Do not create empty directories for unused modes. Save the recipe before rendering,
and keep accepted recipes unchanged. The helper writes a receipt beside each render
with source metadata, effective RAW settings/decoder, renderer version and macOS
version. The receipt is not a substitute for the recipe or its referenced assets.

For another adjustment, copy the selected version's recipe, preserve/correct its
relative paths, change the requested values and use a fresh output filename. Run
`render` on the new recipe, then inspect the image. Keep the original recipe and
accepted render. For RAW replay, use the recorded decoder version when available;
system defaults and rendering may change after macOS updates. Do not blindly copy
unsupported default RAW controls from a receipt into a new recipe.

The script intentionally does not implement approval: the agent must follow the
confirmation step in `SKILL.md` before executing a retouch recipe. Low-level helpers
remain usable for the explicitly permitted analysis preview and mask annotation.

## Native API references

- [Apple CIRAWFilter](https://developer.apple.com/documentation/coreimage/cirawfilter)
- [Apple CIContext export](https://developer.apple.com/documentation/coreimage/cicontext)
- [Apple foreground instance mask request](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest)

Consult current documentation or the installed SDK for advanced operations. The
presence of a system API does not replace validation on the user's actual image.
