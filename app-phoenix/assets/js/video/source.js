import { createRequestScope } from "../map/data/request_scope.js"
import { toVideoPoints } from "./points.js"

const EMPTY = { type: "FeatureCollection", features: [] }

export function createVideoSource(source) {
  const operations = createRequestScope()
  const fixed = Boolean(source.fixedRange)

  async function load({ signal } = {}) {
    const operation = operations.begin(signal)
    try {
      const snapshot = await operation.wait(
        source.snapshot({ purpose: "video", signal: operation.signal }),
      )
      operation.check()
      return {
        trackGeojson: snapshot.geojson ?? EMPTY,
        points: toVideoPoints(snapshot.points),
        range: snapshot.range ?? {},
        revision: snapshot.revision,
        title: fixed ? (snapshot.title ?? "") : "",
      }
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

  return {
    fixed,
    load,
    applyDates,
    reset: () => operations.reset(),
    destroy: () => operations.destroy(),
  }
}
