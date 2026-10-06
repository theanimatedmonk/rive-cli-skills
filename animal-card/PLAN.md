# Animal Card: Plan (v0, brainstorm)

> **Status:** discussion only. No code yet. This is the spec we iterate on before building anything.

---

## Intent

When the bird-sound app identifies a bird (BirdNET), it shows a **bird card**: the species, facts from Wikipedia, and artwork in the style of the reference playing cards. The reference has:

- flat geometric shapes
- bold ink outlines
- a small earthy palette
- feathers filled with dots, chevrons and stripes
- mirrored court-card layouts
- a cream paper frame with suit and rank in the corners

The artwork must be **made procedurally from the bird's photo**, not generated per request by an image model:

```
BirdNET result ──► Wikipedia photo ──► Rive (image binding) ──► BirdCard
                                                                 ├─ stylize shader: photo → print
                                                                 └─ card chrome: frame, suit, name
```

The same pipeline must work for **any** bird photo and give each species its own look.

---

## Two terms

- **Procedural:** the art is computed by code from the photo, the same way every time. There is no AI drawing step.
- **Madhubani-like:** shorthand for the reference style, which has outlined shapes filled with repeated line patterns. Folk-art styles like Madhubani and Gond share that look.

---

## What a shader can and can't do

This decides what the cards will actually look like, so it comes first.

**A shader can turn the photo into a print of the photo.** Each pixel is recoloured, outlined and patterned based on the photo itself:

| Reference look | Shader technique |
| --- | --- |
| Flat colour areas instead of photo detail | Kuwahara filter (an edge-preserving blur that flattens texture into painted-looking patches), then snap each pixel to a 5–6 colour palette |
| Bold ink outlines | Edge detection on the flattened image (difference of Gaussians), drawn as thick dark lines |
| Double outline around the bird | Two offset strokes along the bird's silhouette (needs a mask, see below) |
| Feathers filled with dots, chevrons, stripes | Each palette colour gets a pattern. Patterns follow the direction of the feathers, read from the photo's gradients, so they bend with the body |
| Cream paper, printed feel | Paper grain, ink layer slightly offset from the colour layer (misregistration), slight wobble in lines |
| Mirrored court card (Queen, King) | Draw the stylized bird twice, the second rotated 180°, split on the diagonal |

**A shader can't redraw the bird.** It can't simplify the anatomy into geometric shapes, change the pose, or invent an illustrated composition the way the reference cards do. The output will read as **"a woodcut or screen print of this photo"**, not "an illustration of this bird".

That gap is smaller than it sounds, because **the card chrome does much of the work**: the frame, corner indices, suit symbols, ornaments (leaves, arrows, clouds) and hand-lettered name are what make the reference read as a card. Those are Rive vector art, designed once, and they look as good as the reference.

---

## The pipeline

### 1. Pick and prepare the image (once per species, cached)

- **Source:** Wikipedia's page summary API gives the lead image (`originalimage`) and a short extract. The lead image is usually a clear, well-lit shot of the bird.
- **Licence check:** the Commons API gives each image's licence. Skip non-free images ("fair use") and fall back to the next image. See [Licensing](#licensing).
- **Crop:** square-ish, centred on the bird.
- **Mask (the bird cut out from the background):** this matters more than anything else for quality. Without it, the background twigs, leaves and sky get outlined and patterned too, and the bird gets lost.
  - **v0, no extra step:** guess the background from the colours along the image border and fade out what matches. Works for sky and plain backgrounds, poor for busy foliage.
  - **v1, recommended:** run a small background-removal model once per species and store the mask as a second image. It is not generative (it only labels pixels as bird or not bird), it takes milliseconds to a second on a CPU, and there are only about 6,500 species to process.

### 2. Bind into Rive

The app binds the photo (and the mask, in v1) to image properties on the card's view model. This works on the web like the tarot card's `face`: `decodeImage` in the page, then set the property.

### 3. Stylize in the card (GPU, at runtime)

A Luau script on the card runs the shader stages in order. Each stage draws to an offscreen canvas that the next stage reads:

1. **Flatten:** Kuwahara filter.
2. **Quantize:** snap to the card's palette, in a perceptual colour space so similar colours group sensibly.
3. **Ink:** edges plus the double outline around the mask.
4. **Patterns:** fill each palette area with its pattern, following the feather direction.
5. **Paper:** grain, misregistration, cream background outside the mask.

The result is static, so it is **computed once and cached**. After that the card only draws a texture, plus cheap animated overlays if we want them. This keeps the heavy filters off phones' per-frame budget.

### 4. Card chrome (Rive vector, data-bound)

- **Frame:** cream card, thin brown border, inner frame line.
- **Corners:** rank and suit, top-left and rotated bottom-right.
- **Ornaments:** a small set of leaf, branch, arrow and cloud motifs, picked per card.
- **Text:** common name in a hand-lettered font along the frame, scientific name, BirdNET confidence.
- **Back of the card:** Wikipedia facts and the photo credit.

---

## Every species looks different, but always the same

A **seed** from the scientific name (a hash) picks, deterministically:

| Choice | Options (to design) |
| --- | --- |
| Palette | 6–8 palettes, all in the reference's family: cream, ink black, rust, teal, mustard, slate blue |
| Pattern set | Which patterns map to which tones: dots, chevrons, stripes, zigzag, scales, hatching |
| Layout | Single bird (number card) or mirrored (court card) |
| Ornaments | Which motifs frame the bird |
| Suit and rank | See the open questions; this could carry meaning instead of being random |

The same bird always gets the same card, so users can collect cards and recognise them again. Different birds look different even when their photos are similar.

---

## The reveal (where Rive pays off)

Because the art is built in stages, the card can **draw itself** when a bird is identified. A `progress` number on the view model drives each stage in turn:

1. The paper and frame fade in.
2. Ink lines draw across the bird.
3. Colour floods into the areas.
4. Patterns stamp in.
5. The name is lettered on.

An image model can't give us this. It is also the same trick as the tarot reveal: the moment of identification becomes the animation.

---

## Alternative: AI images per species, made once

The scalability worry is about calling an image model **per request**. But the species list is finite: BirdNET covers about 6,500 species. A one-off batch, one image per species, cached and served like any other image, would cost roughly a few cents per image, so a few hundred dollars once. It would not be a per-user cost.

| | Procedural (this plan) | AI per species, batch once |
| --- | --- | --- |
| Look | Print of the photo; consistent | Real illustrations; closest to the reference |
| Consistency across 6,500 cards | Guaranteed by construction | Drifts; needs review and reruns |
| Cost | Free per card | One-off batch, then storage |
| New photo, user upload | Works instantly | Needs a new generation |
| Animated reveal | Yes, stage by stage | Only a fade or wipe of the finished image |
| Licensing | Derivative of the source photo | Depends on the model's terms; still shaped by the source photo |
| Effort | Shader work and tuning | Prompting, review pipeline, retries |

**Recommendation:** build the procedural system as the default, since it works for every bird and every photo, including user uploads, and gives the drawing reveal. If some cards look weak, swap in hand-made or AI cards for the most common few hundred species later. The card chrome and reveal stay the same either way.

---

## Licensing

Most Wikipedia bird photos are **CC BY** or **CC BY-SA**. Stylizing a photo makes a derivative of it:

- **Attribution** is required: photographer and licence, on the card (the back is fine).
- **CC BY-SA** means the stylized card is also CC BY-SA. That's fine for display in the app; it matters if cards are sold or bundled as artwork.
- **Non-free** images (fair use) must be skipped, which the Commons licence check handles.

Not legal advice. Worth a proper check before launch, especially if cards become collectable or sellable.

---

## Risks and spikes (do these first)

1. **Can a shader read a data-bound image? Yes (spike done 2026-10-06, `spike/`).** A node script reads the view model's `photo` and runs a posterize shader on it two ways: sampling `photo.value:view()` directly, and drawing it into a `context:canvas()` first and sampling that. Both work in:
   - the CLI's native renderer, with the default image asset bound
   - a signed web build (`@rive-app/webgl2@2.44.0`, `enableGPUCanvas: true`), both with the default asset and with a Wikipedia photo the page decodes (`rive.decodeImage`) and binds at runtime. That second case is exactly the bird app's flow.

   **Notes:**
   - Binds only apply while a state machine runs: the card artboard needs one, even an idle one.
   - The docs warn that a `view()` taken from an image *asset* samples as zeros. That didn't happen in either runtime tested. Still, the canvas copy (route C) is the safe default: it costs one small draw and also sets the working resolution for the filters.
   - Ten Rings' web limitation was `context:decodeImage` *inside a script*. It doesn't apply here, because the page decodes and the script only receives the image.
   - **Not yet tested:** the Rive editor, and the iOS and Android runtimes. Check them before committing to mobile.
   - **The fallback is no longer needed:** stylizing stays in Rive, and the reveal can animate the live stages.
2. **Mask quality:** test the v0 border heuristic on 30 varied Wikipedia photos before deciding whether v1 is needed from day one.
3. **Photo variety:** tiny birds in clutter, backlit birds, odd crops. Measure on the same 30 photos and tune the filters to the worst cases, not the best.
4. **Performance on phones:** the Kuwahara filter is the heaviest stage. Run once at card size and cache; measure on a mid-range Android.
5. **Taste:** the tuning of palette, pattern scale and line weight decides whether it looks like the reference or like an Instagram filter. Budget real time for this.

---

## Rive structure (first sketch)

```
BirdCard (artboard, the card face; VM bound here)
  ├── Paper          cream background, grain
  ├── Art            ScriptedDrawable  BirdStylize.luau + stage shaders
  ├── Chrome         frame, corner rank and suit, ornaments (vector)
  └── Lettering      common name, scientific name, confidence (data-bound text)
```

**View model `BirdCard`:**

| Property | Type | Purpose |
| --- | --- | --- |
| `photo` | image | Wikipedia photo |
| `mask` | image | Bird cut-out (v1) |
| `commonName`, `scientificName` | string | Lettering |
| `seed` | number | Picks palette, patterns, layout, ornaments |
| `confidence` | number | BirdNET confidence, shown on the card |
| `progress` | number | 0–1, drives the drawing reveal |
| `reveal` | trigger | Plays the reveal |

---

## Build order

1. **Spike:** a bound image sampled in a shader, on web and native (risk 1). The answer decides the architecture.
2. **Test set:** 30 varied Wikipedia bird photos, with v0 masks.
3. **Stylize stages,** one at a time, checked against the test set: flatten, quantize, ink, patterns, paper.
4. **Card chrome** in Rive: frame, corners, two or three ornament sets, lettering.
5. **Seed:** palettes, pattern sets, layouts.
6. **Reveal** animation driven by `progress`.
7. **Web demo:** pick or upload a bird, see its card. Then wire to BirdNET and Wikipedia.

---

## Open questions

1. **Suit and rank:** random from the seed, or meaningful? For example, suit by habitat (forest, wetland, open country, sea) and rank by how rare the bird is in the user's region, so a rare find is a King.
2. **Card back:** Wikipedia facts and credit on the back, with a flip like the tarot card?
3. **Platforms:** the web first, or the mobile app from the start? This affects spike 1.
4. **User photos:** should users be able to stylize their own bird photos too? The procedural approach allows it; it also raises moderation questions.
5. **How close to the reference?** Is "a print of the photo with beautiful card chrome" good enough, or must it look illustrated? If illustrated, the hybrid route (batch-made art for common species) moves up.
