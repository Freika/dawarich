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

const loadedBySet = new WeakMap()

export function fontByKey(key) {
  return POSTER_FONTS.find((font) => font.key === key) || POSTER_FONTS[0]
}

export async function ensurePosterFont(
  key,
  urls,
  { fonts = globalThis.document?.fonts, FontFace = globalThis.FontFace } = {},
) {
  const font = fontByKey(key)
  const loaded = loadedBySet.get(fonts) ?? new Set()
  loadedBySet.set(fonts, loaded)
  if (loaded.has(font.key)) return font.family

  const faces = ["400", "700"].map((weight) => {
    const url = urls[`${font.key}-${weight}`]
    if (!url) return null
    return new FontFace(font.family, `url(${url})`, { weight })
  })

  await Promise.all(
    faces.filter(Boolean).map(async (face) => {
      fonts.add(await face.load())
    }),
  )

  loaded.add(font.key)
  return font.family
}
