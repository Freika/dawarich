import {
  detectMaxRenderDimension,
  PAPER_SIZES,
  resolveExportGeometry,
} from "poster_studio/data/paper_sizes"

// Poster layout presets. Print layouts are physical (paper key + DPI math),
// the rest are pixel-exact screen formats (no DPI chunk in the PNG).
export const LAYOUT_CATEGORIES = [
  {
    id: "print",
    layouts: [
      paper("print-a5", "A5"),
      paper("print-a4", "A4"),
      paper("print-a3", "A3"),
      paper("print-a2", "A2"),
      paper("print-a1", "A1"),
      paper("print-a0", "A0"),
      paper("print-30x40", "P30X40"),
      paper("print-50x70", "P50X70"),
      paper("print-70x100", "P70X100"),
      paper("print-letter", "LETTER"),
      paper("print-a4-landscape", "A4", true),
      paper("print-a3-landscape", "A3", true),
    ],
  },
  {
    id: "social",
    layouts: [
      pixels("social-ig-square", 1080, 1080),
      pixels("social-ig-portrait", 1080, 1350),
      pixels("social-story", 1080, 1920),
      pixels("social-x-header", 1500, 500),
      pixels("social-youtube-thumb", 1280, 720),
    ],
  },
  {
    id: "wallpaper",
    layouts: [
      pixels("wallpaper-fhd", 1920, 1080),
      pixels("wallpaper-4k", 3840, 2160),
      pixels("wallpaper-ultrawide", 3440, 1440),
      pixels("wallpaper-phone", 1179, 2556),
      pixels("wallpaper-tablet", 2064, 2752),
    ],
  },
]

export const DEFAULT_LAYOUT_ID = "print-a3"

function paper(id, paperKey, landscape = false) {
  const size = PAPER_SIZES[paperKey]
  const [wmm, hmm] = landscape ? [size.hmm, size.wmm] : [size.wmm, size.hmm]
  return {
    id,
    kind: "paper",
    paperKey,
    landscape,
    aspect: wmm / hmm,
    dimensionsLabel: `${wmm / 10} × ${hmm / 10} cm`,
  }
}

function pixels(id, width, height) {
  return {
    id,
    kind: "pixels",
    width,
    height,
    aspect: width / height,
    dimensionsLabel: `${width} × ${height} px`,
  }
}

export function layoutById(id) {
  for (const category of LAYOUT_CATEGORIES) {
    const layout = category.layouts.find((entry) => entry.id === id)
    if (layout) return layout
  }
  return layoutById(DEFAULT_LAYOUT_ID)
}

// Export pixel geometry for any layout kind, honoring the device GL limit.
// Paper layouts keep the DPI step-down semantics; pixel layouts scale down
// proportionally in the (unlikely) case they exceed the limit.
export function resolveLayoutGeometry(layout, dpi, options = {}) {
  if (layout.kind === "paper") {
    return resolveExportGeometry(layout.paperKey, dpi, {
      ...options,
      landscape: layout.landscape,
    })
  }

  const maxDimensionPx = options.maxDimensionPx ?? detectMaxRenderDimension()
  const longest = Math.max(layout.width, layout.height)
  const scale = Math.min(1, maxDimensionPx / longest)
  return {
    width: Math.round(layout.width * scale),
    height: Math.round(layout.height * scale),
    requestedDpi: 0,
    effectiveDpi: 0,
    steppedDown: scale < 1,
    maxDimensionPx,
  }
}
