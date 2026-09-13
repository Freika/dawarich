export const MM_PER_INCH = 25.4

export const PAPER_SIZES = {
  A5: { wmm: 148, hmm: 210 },
  A4: { wmm: 210, hmm: 297 },
  A3: { wmm: 297, hmm: 420 },
  A2: { wmm: 420, hmm: 594 },
  A1: { wmm: 594, hmm: 841 },
  A0: { wmm: 841, hmm: 1189 },
  LETTER: { wmm: 216, hmm: 279 },
  P30X40: { wmm: 300, hmm: 400 },
  P50X70: { wmm: 500, hmm: 700 },
  P70X100: { wmm: 700, hmm: 1000 },
}

export const DPI_PRESETS = [96, 150, 300]

// Conservative when no WebGL context is available (worker, SSR, probe failure).
export const SAFE_FALLBACK_MAX_DIMENSION = 8192
// 2D canvas per-side cap on the strictest mainstream engines.
export const CANVAS_MAX_DIMENSION = 16384

export function paperPixels(paperKey, dpi, { landscape = false } = {}) {
  const paper = PAPER_SIZES[paperKey]
  if (!paper) throw new Error(`Unknown paper size "${paperKey}"`)
  let width = Math.round((paper.wmm / MM_PER_INCH) * dpi)
  let height = Math.round((paper.hmm / MM_PER_INCH) * dpi)
  if (landscape) [width, height] = [height, width]
  return { width, height }
}

// Largest DPI whose longest side still fits maxDimensionPx (silent step-down).
export function clampDpiToLimit(paperKey, dpi, maxDimensionPx) {
  const paper = PAPER_SIZES[paperKey]
  if (!paper) throw new Error(`Unknown paper size "${paperKey}"`)
  const longestMm = Math.max(paper.wmm, paper.hmm)
  const maxDpi = Math.floor((maxDimensionPx * MM_PER_INCH) / longestMm)
  return Math.min(dpi, Math.max(1, maxDpi))
}

export function detectMaxRenderDimension() {
  if (typeof document === "undefined") return SAFE_FALLBACK_MAX_DIMENSION
  try {
    const canvas = document.createElement("canvas")
    const gl = canvas.getContext("webgl2") || canvas.getContext("webgl")
    if (!gl) return SAFE_FALLBACK_MAX_DIMENSION
    const glMax = Math.min(
      gl.getParameter(gl.MAX_RENDERBUFFER_SIZE),
      gl.getParameter(gl.MAX_TEXTURE_SIZE),
    )
    return Math.min(glMax, CANVAS_MAX_DIMENSION)
  } catch {
    return SAFE_FALLBACK_MAX_DIMENSION
  }
}

// Resolves the effective export geometry for a paper/dpi against the device cap:
// keeps the requested dpi when it fits, else steps dpi down and reports it.
export function resolveExportGeometry(paperKey, dpi, options = {}) {
  const { landscape = false, maxDimensionPx = detectMaxRenderDimension() } =
    options
  const effectiveDpi = clampDpiToLimit(paperKey, dpi, maxDimensionPx)
  const { width, height } = paperPixels(paperKey, effectiveDpi, { landscape })
  return {
    width,
    height,
    requestedDpi: dpi,
    effectiveDpi,
    steppedDown: effectiveDpi < dpi,
    maxDimensionPx,
  }
}
