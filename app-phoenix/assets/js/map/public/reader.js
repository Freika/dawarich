import { createRequestScope } from "../data/request_scope.js"
export function createPublicReader({
  shareId,
  origin = globalThis.location.origin,
  fetch = globalThis.fetch.bind(globalThis),
  timers = globalThis,
} = {}) {
  if (
    typeof shareId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      shareId,
    )
  )
    throw new Error("Invalid public capability")
  const scope = createRequestScope(timers)
  async function read(resource, params = {}, { signal } = {}) {
    if (
      !["metadata", "points", "route", "photos", "thumbnail"].includes(resource)
    )
      throw new Error("Unsupported public read")
    const suffix =
      resource === "thumbnail"
        ? `photos/${encodeURIComponent(params.id)}/thumbnail`
        : resource
    const url = new URL(`/native/public/maps/${shareId}/${suffix}`, origin)
    if (resource === "thumbnail" && typeof params.source === "string")
      url.searchParams.set("source", params.source)
    const operation = scope.begin(signal, 15000)
    try {
      const response = await operation.wait(
        fetch(url.href, {
          signal: operation.signal,
          credentials: "same-origin",
          headers: {
            Accept:
              resource === "thumbnail" ? "image/jpeg" : "application/json",
          },
        }),
      )
      operation.check()
      if (!response.ok) throw new Error("Public read refused")
      let data = await operation.wait(
        resource === "thumbnail" ? response.blob() : response.json(),
      )
      operation.check()
      if (resource === "photos")
        data = data.map((photo) => ({ ...photo, capturedAt: photo.taken_at }))
      return { data, headers: response.headers }
    } finally {
      operation.close()
    }
  }
  return {
    read,
    async pages(resource, params, options = {}) {
      if (resource !== "photos") throw new Error("Unsupported public page")
      const response = await read(resource, params, options)
      options.onPage?.(response)
      return response.data
    },
    reset: () => scope.reset(),
    destroy: () => scope.destroy(),
  }
}
