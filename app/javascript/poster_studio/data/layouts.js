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
    name: "Print",
    layouts: [
      paper("print-a5", "A5 Portrait", "A5"),
      paper("print-a4", "A4 Portrait", "A4"),
      paper("print-a3", "A3 Portrait", "A3"),
      paper("print-a2", "A2 Portrait", "A2"),
      paper("print-a1", "A1 Portrait", "A1"),
      paper("print-a0", "A0 Portrait", "A0"),
      paper("print-30x40", "30 × 40 cm", "P30X40"),
      paper("print-50x70", "50 × 70 cm", "P50X70"),
      paper("print-70x100", "70 × 100 cm", "P70X100"),
      paper("print-letter", "Letter (US)", "LETTER"),
      paper("print-a4-landscape", "A4 Landscape", "A4", true),
      paper("print-a3-landscape", "A3 Landscape", "A3", true),
    ],
  },
  {
    id: "social",
    name: "Social",
    layouts: [
      pixels("social-ig-square", "Instagram Square", 1080, 1080),
      pixels("social-ig-portrait", "Instagram Portrait", 1080, 1350),
      pixels("social-story", "Story (9:16)", 1080, 1920),
      pixels("social-x-header", "X Header", 1500, 500),
      pixels("social-youtube-thumb", "YouTube Thumbnail", 1280, 720),
    ],
  },
  {
    id: "wallpaper",
    name: "Wallpaper",
    layouts: [
      pixels("wallpaper-fhd", "Desktop Full HD", 1920, 1080),
      pixels("wallpaper-4k", "Desktop 4K", 3840, 2160),
      pixels("wallpaper-ultrawide", "Desktop Ultrawide", 3440, 1440),
      pixels("wallpaper-phone", "Phone", 1179, 2556),
      pixels("wallpaper-tablet", "Tablet", 2064, 2752),
    ],
  },
]

export const DEFAULT_LAYOUT_ID = "print-a3"

function paper(id, name, paperKey, landscape = false) {
  const size = PAPER_SIZES[paperKey]
  const [wmm, hmm] = landscape ? [size.hmm, size.wmm] : [size.wmm, size.hmm]
  return {
    id,
    name,
    kind: "paper",
    paperKey,
    landscape,
    aspect: wmm / hmm,
    dimensionsLabel: `${wmm / 10} × ${hmm / 10} cm`,
  }
}

function pixels(id, name, width, height) {
  return {
    id,
    name,
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
