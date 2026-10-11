export const EXPORT_TIMEOUT_MS = 300_000

export const aborted = () =>
  new DOMException("Poster export aborted", "AbortError")

export async function captureBounds({
  library,
  style,
  bounds,
  width,
  height,
  cssSize,
  signal,
  timeoutMs = EXPORT_TIMEOUT_MS,
  document: doc = globalThis.document,
  timers = globalThis,
}) {
  if (signal?.aborted) throw aborted()
  const cssWidth = Math.round(cssSize?.width ?? width)
  const cssHeight = Math.round(cssSize?.height ?? height)
  const pixelRatio = width / cssWidth

  const container = doc.createElement("div")
  container.style.cssText = `position:fixed;left:-99999px;top:0;width:${cssWidth}px;height:${cssHeight}px;pointer-events:none;`
  doc.body.appendChild(container)
  const cleanups = []
  let map = null

  try {
    map = new library.Map({
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

    await new Promise((resolve, reject) => {
      const onIdle = () => resolve()
      const onError = (event) =>
        reject(event?.error ?? new Error("MapLibre error"))
      const onAbort = () => reject(aborted())
      const timer = timers.setTimeout(
        () => reject(new Error("Poster export timed out")),
        timeoutMs,
      )
      map.once("idle", onIdle)
      map.once("error", onError)
      signal?.addEventListener("abort", onAbort, { once: true })
      cleanups.push(() => {
        timers.clearTimeout(timer)
        map.off("idle", onIdle)
        map.off("error", onError)
        signal?.removeEventListener("abort", onAbort)
      })
    })

    const out = doc.createElement("canvas")
    out.width = width
    out.height = height
    out.getContext("2d").drawImage(map.getCanvas(), 0, 0, width, height)
    return out
  } finally {
    for (const cleanup of cleanups) cleanup()
    map?.remove()
    container.remove()
  }
}
