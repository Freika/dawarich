const MAX_POINTS = 10000

export function createSelectionQuery({ reader }) {
  async function select(bounds, range, { signal } = {}) {
    const window = { start_at: range.startAt, end_at: range.endAt }
    const points = {
      ...window,
      min_longitude: String(bounds.minLng),
      max_longitude: String(bounds.maxLng),
      min_latitude: String(bounds.minLat),
      max_latitude: String(bounds.maxLat),
      include_anomalies: "true",
    }
    if (range.importId) points.import_id = String(range.importId)
    const [rows, visits] = await Promise.all([
      reader.pages("points", points, { signal, maxRows: MAX_POINTS }),
      reader.read(
        "visits",
        {
          ...window,
          selection: "true",
          sw_lat: String(bounds.minLat),
          sw_lng: String(bounds.minLng),
          ne_lat: String(bounds.maxLat),
          ne_lng: String(bounds.maxLng),
        },
        { signal },
      ),
    ])
    return { points: rows, visits: visits.data || [] }
  }

  return { select }
}
