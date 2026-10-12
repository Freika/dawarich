// Self-hosted OFL fonts for poster typography (no runtime Google Fonts).
// Files live in app/assets/fonts/poster/; the studio view passes their
// digested asset URLs via a data attribute, keyed as "<key>-<weight>".
export const POSTER_FONTS = [
  { key: "inter", label: "Inter", family: "Poster Inter" },
  { key: "oswald", label: "Oswald", family: "Poster Oswald" },
  {
    key: "playfair-display",
    label: "Playfair Display",
    family: "Poster Playfair Display",
  },
  {
    key: "jetbrains-mono",
    label: "JetBrains Mono",
    family: "Poster JetBrains Mono",
  },
]

export const DEFAULT_FONT_KEY = "oswald"

const loaded = new Set()

export function fontByKey(key) {
  return POSTER_FONTS.find((font) => font.key === key) || POSTER_FONTS[0]
}

// Loads both weights of a family into document.fonts; safe to call again.
export async function ensurePosterFont(key, urls) {
  const font = fontByKey(key)
  if (loaded.has(font.key)) return font.family

  const faces = ["400", "700"].map((weight) => {
    const url = urls[`${font.key}-${weight}`]
    if (!url) return null
    return new FontFace(font.family, `url(${url})`, { weight })
  })

  await Promise.all(
    faces.filter(Boolean).map(async (face) => {
      document.fonts.add(await face.load())
    }),
  )

  loaded.add(font.key)
  return font.family
}
