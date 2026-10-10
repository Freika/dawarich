import { createRequestScope } from "./request_scope.js"

const paths = {
  points: "points",
  tracks: "tracks",
  track: "tracks/:id",
  track_points: "tracks/:id/points",
  settings: "settings",
  bounds: "bounds",
  photos: "photos",
  thumbnail: "photos/:id/thumbnail",
  locations: "locations",
  suggestions: "locations/suggestions",
  places: "places",
  place_search: "places/search",
  nearby: "places/nearby",
  visits: "visits",
  areas: "areas",
  timeline: "timeline",
  hexagons: "hexagons",
  fog: "fog",
}

export function createReader({
  origin = globalThis.location.origin,
  fetch = globalThis.fetch.bind(globalThis),
  maxPages = 100,
  maxRows = 100000,
  timers = globalThis,
  timeoutMs = 15000,
} = {}) {
  const scope = createRequestScope(timers)

  function url(resource, params) {
    if (!Object.hasOwn(paths, resource) || Object.hasOwn(params, "api_key"))
      throw new Error("Unsupported map read")
    const path = paths[resource].replace(":id", () => {
      if (params.id == null) throw new Error("Missing resource identity")
      return encodeURIComponent(params.id)
    })
    const result = new URL(`/native/map/data/${path}`, origin)
    for (const [key, value] of Object.entries(params)) {
      if (value == null || key === "id") continue
      for (const entry of Array.isArray(value) ? value : [value])
        result.searchParams.append(
          Array.isArray(value) ? `${key}[]` : key,
          entry,
        )
    }
    return result
  }

  async function read(resource, params = {}, { signal, onData } = {}) {
    const operation = scope.begin(signal, timeoutMs)
    try {
      const response = await fetch(url(resource, params).href, {
        signal: operation.signal,
        credentials: "same-origin",
        headers: { Accept: "application/json" },
      })
      operation.check()
      const data = response.status === 204 ? [] : await response.json()
      operation.check()
      const noData =
        resource === "bounds" &&
        response.status === 404 &&
        data.point_count === 0
      if (!response.ok && !noData) {
        const error = new Error("Map read failed")
        error.status = response.status
        throw error
      }
      const result = {
        status: noData ? "no_data" : "ok",
        data,
        headers: response.headers,
        revision: operation.revision,
      }
      onData?.(result)
      return result
    } finally {
      operation.close()
    }
  }

  async function pages(resource, params = {}, options = {}) {
    const operation = scope.begin(options.signal, timeoutMs)
    const pageLimit = options.maxPages ?? maxPages
    const rowLimit = options.maxRows ?? maxRows
    const rows = []
    try {
      for (let page = 1; page <= pageLimit; page++) {
        const result = await read(
          resource,
          { ...params, page, per_page: params.per_page ?? 1000 },
          { signal: operation.signal },
        )
        operation.check()
        if (!Array.isArray(result.data)) throw new Error("Invalid map page")
        rows.push(...result.data)
        if (rows.length > rowLimit) throw new Error("Map row limit exceeded")
        options.onPage?.(result)
        const totalValue = result.headers.get("x-total-pages")
        const total = Number(totalValue)
        if (totalValue === null || !Number.isInteger(total) || total < 0)
          throw new Error("Invalid map pagination")
        if (page >= total) return rows
      }
      throw new Error("Map page limit exceeded")
    } finally {
      operation.close()
    }
  }

  return {
    read,
    pages,
    reset: () => scope.reset(),
    destroy: () => scope.destroy(),
    get revision() {
      return scope.revision
    },
  }
}
