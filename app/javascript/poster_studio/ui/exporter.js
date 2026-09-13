import { resolveLayoutGeometry } from "poster_studio/data/layouts"
import { PAPER_SIZES } from "poster_studio/data/paper_sizes"
import { pdfBlob, pngBlob } from "poster_studio/export/download"
import { encodePdf } from "poster_studio/export/pdf_encoder"
import { encodePng } from "poster_studio/export/png_encoder"
import { captureBounds } from "poster_studio/render/offscreen_map"
import { drawOverlay } from "poster_studio/render/overlay"

// Renders the studio's current state into a downloadable blob: offscreen
// map at export resolution, then the same overlay pass the preview uses.
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
}) {
  const geometry = resolveLayoutGeometry(layout, dpi)
  const canvas = await captureBounds({
    style,
    bounds,
    width: geometry.width,
    height: geometry.height,
    cssSize,
    signal,
  })
  drawOverlay(canvas, { theme, ...text, font })

  if (format === "pdf" && layout.kind === "paper") {
    const paper = PAPER_SIZES[layout.paperKey]
    const [widthMm, heightMm] = layout.landscape
      ? [paper.hmm, paper.wmm]
      : [paper.wmm, paper.hmm]
    const bytes = await encodePdf(canvas, { widthMm, heightMm })
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
  return { blob: pngBlob(bytes), extension: "png", geometry }
}

export function studioFilename(title, layout, extension) {
  const slug = (title || "poster")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "")
  return `dawarich-${slug || "poster"}-${layout.id}.${extension}`
}
