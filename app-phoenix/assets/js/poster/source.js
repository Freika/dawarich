import { createRequestScope } from "../map/data/request_scope.js"

const EMPTY = { type: "FeatureCollection", features: [] }

export function createPosterSource(
  source,
  { fallbackBounds = () => null } = {},
) {
  const operations = createRequestScope()
  const fixed = Boolean(source.fixedRange)

  async function load({ signal } = {}) {
    const operation = operations.begin(signal)
    try {
      const snapshot = await operation.wait(
        source.snapshot({ purpose: "poster", signal: operation.signal }),
      )
      operation.check()
      return project(snapshot)
    } finally {
      operation.close()
    }
  }

  async function applyDates(range, { signal } = {}) {
    if (fixed) throw new Error("Trip range is fixed")
    operations.reset()
    const operation = operations.begin(signal)
    try {
      await operation.wait(
        source.applyDates(range, { signal: operation.signal }),
      )
      operation.check()
    } finally {
      operation.close()
    }
    return load({ signal })
  }

  function project(snapshot) {
    return {
      ...snapshot,
      geojson: snapshot.geojson ?? EMPTY,
      guardCoords: guardCoords(snapshot.points ?? []),
      flightsOmitted: (snapshot.flights?.features?.length ?? 0) > 0,
      defaultTitle: fixed ? (snapshot.title ?? "") : "",
      timeZone: snapshot.range?.timezone || undefined,
    }
  }

  return {
    fixed,
    trackSource: fixed ? "routes" : "tracks",
    load,
    applyDates,
    fallbackBounds: () => (fixed ? null : fallbackBounds()),
    destroy: () => operations.destroy(),
  }
}

function guardCoords(points) {
  const coords = []
  for (const point of points) {
    const lon = Number(point.longitude)
    const lat = Number(point.latitude)
    if (Number.isFinite(lon) && Number.isFinite(lat)) coords.push([lon, lat])
  }
  return coords
}
