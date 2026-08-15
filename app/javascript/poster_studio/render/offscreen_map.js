import maplibregl from "maplibre-gl"

// Renders `style` over `bounds` into a detached canvas at exactly width x height.
// The GL backing store equals the target pixels (callers clamp width/height to
// the device GL limit first).
//
// Pass `cssSize` (the preview's on-screen size) to keep WYSIWYG cartography:
// the hidden map then uses the preview's CSS size — so fitBounds resolves to
// the SAME zoom the preview showed (same tile detail, same relative stroke
// weights) — and reaches the export resolution via pixelRatio instead of a
// bigger viewport, which would bump the zoom and change the look.
export async function captureBounds({
  style,
  bounds,
  width,
  height,
  cssSize,
  signal,
}) {
  const cssWidth = Math.round(cssSize?.width ?? width)
  const cssHeight = Math.round(cssSize?.height ?? height)
  const pixelRatio = width / cssWidth

  const container = document.createElement("div")
  container.style.cssText = `position:fixed;left:-99999px;top:0;width:${cssWidth}px;height:${cssHeight}px;pointer-events:none;`
  document.body.appendChild(container)

  const map = new maplibregl.Map({
    container,
    style,
    bounds,
    fitBoundsOptions: { padding: 0, animate: false },
    interactive: false,
    attributionControl: false,
    preserveDrawingBuffer: true,
    fadeDuration: 0,
    pixelRatio,
  })

  try {
    await new Promise((resolve, reject) => {
      const onAbort = () => reject(new Error("Poster export aborted"))
      map.once("idle", () => {
        signal?.removeEventListener("abort", onAbort)
        resolve()
      })
      map.once("error", (event) =>
        reject(event.error ?? new Error("MapLibre error")),
      )
      signal?.addEventListener("abort", onAbort, { once: true })
    })

    const out = document.createElement("canvas")
    out.width = width
    out.height = height
    out.getContext("2d").drawImage(map.getCanvas(), 0, 0, width, height)
    return out
  } finally {
    map.remove()
    container.remove()
  }
}
