// Loads the HUD's typefaces before rendering, so canvas text draws with the
// design's fonts instead of the fallback stack. Reuses the self-hosted OFL
// faces the poster studio already ships (app/assets/fonts/poster/) — no
// runtime Google Fonts request, which self-hosted instances must not make.
// The studio view passes digested asset URLs keyed "<key>-<weight>", the same
// contract poster_studio/data/fonts.js uses.
export const HUD_MONO_FAMILY = "Video HUD Mono"
export const HUD_SANS_FAMILY = "Video HUD Sans"

const FACES = [
  { family: HUD_MONO_FAMILY, key: "jetbrains-mono", weight: "400" },
  { family: HUD_MONO_FAMILY, key: "jetbrains-mono", weight: "700" },
  { family: HUD_SANS_FAMILY, key: "inter", weight: "400" },
  { family: HUD_SANS_FAMILY, key: "inter", weight: "700" },
]

const FALLBACK = { mono: "monospace", sans: "sans-serif" }
const LOAD_TIMEOUT_MS = 3000

let fontsPromise = null

// Resolves to the family names to draw with. Capped by a timeout so a slow or
// missing asset degrades to the fallback stack instead of stalling a render.
export function ensureHudFonts(urls) {
  if (fontsPromise) return fontsPromise
  if (!urls || typeof FontFace !== "function") {
    return Promise.resolve(FALLBACK)
  }

  fontsPromise = (async () => {
    const loads = FACES.map(async ({ family, key, weight }) => {
      const url = urls[`${key}-${weight}`]
      if (!url) return
      const face = new FontFace(family, `url(${url})`, { weight })
      document.fonts.add(await face.load())
    })

    const loaded = await Promise.race([
      Promise.all(loads).then(() => true),
      new Promise((resolve) =>
        setTimeout(() => resolve(false), LOAD_TIMEOUT_MS),
      ),
    ]).catch(() => false)

    return loaded ? { mono: HUD_MONO_FAMILY, sans: HUD_SANS_FAMILY } : FALLBACK
  })()

  return fontsPromise
}
