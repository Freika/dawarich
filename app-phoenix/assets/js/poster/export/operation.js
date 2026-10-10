import { downloadBlob } from "./download.js"
import { exportPoster as renderPoster, studioFilename } from "./render.js"

export function createPosterExports({
  exportPoster = renderPoster,
  download = downloadBlob,
} = {}) {
  let current = null

  async function run(request, { deliver = true } = {}) {
    if (current) return { status: "busy" }
    const operation = { controller: new AbortController() }
    current = operation
    try {
      const result = await exportPoster({
        ...request,
        signal: operation.controller.signal,
      })
      if (current !== operation || operation.controller.signal.aborted)
        return { status: "cancelled" }
      if (deliver)
        download(
          result.blob,
          studioFilename(request.title, request.layout, result.extension),
        )
      return { status: "done", geometry: result.geometry, blob: result.blob }
    } catch (error) {
      if (current !== operation || error?.name === "AbortError")
        return { status: "cancelled" }
      return { status: "failed", error }
    } finally {
      if (current === operation) current = null
    }
  }

  return {
    run,
    cancel() {
      current?.controller.abort()
      current = null
    },
    get busy() {
      return current !== null
    },
  }
}
