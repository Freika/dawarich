import { createRequestScope } from "../data/request_scope.js"
export function createPublicStatsReader({
  origin = globalThis.location.origin,
  fetch = globalThis.fetch.bind(globalThis),
  timers = globalThis,
} = {}) {
  const scope = createRequestScope(timers)
  return {
    async read(resource, params, { signal } = {}) {
      if (
        resource !== "hexagons" ||
        typeof params.uuid !== "string" ||
        !params.uuid
      )
        throw new Error("Unsupported public read")
      const operation = scope.begin(signal, 15000)
      try {
        const url = new URL("/api/v1/maps/hexagons", origin)
        url.searchParams.set("uuid", params.uuid)
        const response = await operation.wait(
          fetch(url.href, {
            signal: operation.signal,
            credentials: "omit",
            headers: { Accept: "application/json" },
          }),
        )
        operation.check()
        if (!response.ok) throw new Error("Public stats unavailable")
        const data = await operation.wait(response.json())
        operation.check()
        return { data }
      } finally {
        operation.close()
      }
    },
    reset: () => scope.reset(),
    destroy: () => scope.destroy(),
  }
}
