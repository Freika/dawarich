import { resolveLayoutGeometry } from "./data/layouts.js"
import { interpolate as fill } from "./strings.js"

export function bindExportControls({
  find,
  on,
  studio,
  exports,
  strings = {},
  loadLibrary,
  maxDimensionPx,
  setStatus,
}) {
  const button = find("download")
  const setBusy = (busy) => {
    if (button) button.disabled = busy
  }

  on(button, "click", async () => {
    const request = studio.exportRequest()
    if (exports.busy || !request) return
    const geometry = resolveLayoutGeometry(request.layout, request.dpi, {
      maxDimensionPx,
    })
    setBusy(true)
    setStatus(fill(strings.rendering, geometry))
    try {
      const library = await loadLibrary()
      const result = await exports.run({ ...request, library, maxDimensionPx })
      if (result.status === "done")
        setStatus(
          result.geometry.steppedDown
            ? fill(strings.saved_at_dpi, { dpi: result.geometry.effectiveDpi })
            : (strings.saved ?? ""),
        )
      else if (result.status === "failed")
        setStatus(fill(strings.export_failed, { error: result.error.message }))
      else if (result.status === "cancelled") setStatus("")
    } catch (error) {
      setStatus(fill(strings.export_failed, { error: error.message }))
    } finally {
      setBusy(exports.busy)
    }
  })
}
