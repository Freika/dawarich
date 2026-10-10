import { resolveLayoutGeometry } from "../data/layouts.js"
import { PAPER_SIZES } from "../data/paper_sizes.js"
import { drawOverlay } from "../render/overlay.js"
import { aborted, captureBounds } from "./capture.js"
import { pdfBlob, pngBlob } from "./download.js"
import { encodePdf } from "./pdf_encoder.js"
import { encodePng } from "./png_encoder.js"

const check = (signal) => {
  if (signal?.aborted) throw aborted()
}

export async function exportPoster({
  style,
  bounds,
  layout,
  dpi,
  format,
  theme,
  text,
  font,
  cssSize,
  signal,
  maxDimensionPx,
  library,
  document,
  capture = captureBounds,
}) {
  const geometry = resolveLayoutGeometry(layout, dpi, { maxDimensionPx })
  const canvas = await capture({
    library,
    style,
    bounds,
    width: geometry.width,
    height: geometry.height,
    cssSize,
    signal,
    document,
  })
  try {
    check(signal)
    drawOverlay(canvas, { theme, ...text, font })

    if (format === "pdf" && layout.kind === "paper") {
      const paper = PAPER_SIZES[layout.paperKey]
      const [widthMm, heightMm] = layout.landscape
        ? [paper.hmm, paper.wmm]
        : [paper.wmm, paper.hmm]
      const bytes = await encodePdf(canvas, { widthMm, heightMm })
      check(signal)
      return { blob: pdfBlob(bytes), extension: "pdf", geometry }
    }

    const { data } = canvas
      .getContext("2d")
      .getImageData(0, 0, canvas.width, canvas.height)
    const bytes = encodePng(
      new Uint8Array(data.buffer),
      canvas.width,
      canvas.height,
      geometry.effectiveDpi,
    )
    check(signal)
    return { blob: pngBlob(bytes), extension: "png", geometry }
  } finally {
    canvas.width = 0
    canvas.height = 0
  }
}

export function studioFilename(title, layout, extension) {
  const slug = (title || "poster")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "")
  return `dawarich-${slug || "poster"}-${layout.id}.${extension}`
}
