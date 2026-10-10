export function parseTimestamp(timestamp) {
  if (!timestamp) return null

  if (typeof timestamp === "string") return new Date(timestamp)

  if (typeof timestamp === "number") {
    if (timestamp < 10000000000) return new Date(timestamp * 1000)
    return new Date(timestamp)
  }

  return null
}

export function getTimestamp(point) {
  if (point.properties?.timestamp) return point.properties.timestamp
  if (point.timestamp) return point.timestamp
  return null
}

export function getCoordinates(point) {
  if (!point) return null

  let lon, lat
  if (point.geometry?.coordinates) {
    lon = point.geometry.coordinates[0]
    lat = point.geometry.coordinates[1]
  } else if (point.longitude !== undefined && point.latitude !== undefined) {
    lon = point.longitude
    lat = point.latitude
  } else if (point.lon !== undefined && point.lat !== undefined) {
    lon = point.lon
    lat = point.lat
  } else {
    return null
  }

  return { lon: Number(lon), lat: Number(lat) }
}

export function findTransportationEmoji(point, tracksGeoJSON) {
  if (!tracksGeoJSON?.features?.length) return null

  const timestamp = getTimestamp(point)
  if (!timestamp) return null

  const pointTime = parseTimestamp(timestamp)?.getTime()
  if (!Number.isFinite(pointTime)) return null

  const pointTimeSec = Math.floor(pointTime / 1000)
  for (const track of tracksGeoJSON.features) {
    const startAt = track.properties?.start_at
    const endAt = track.properties?.end_at
    if (!startAt || !endAt) continue

    const trackStart = new Date(startAt).getTime()
    const trackEnd = new Date(endAt).getTime()
    if (pointTime < trackStart || pointTime > trackEnd) continue

    const modeTimeline = track.properties?.mode_timeline
    if (modeTimeline?.length) {
      for (const segment of modeTimeline) {
        if (
          pointTimeSec >= segment.start_time &&
          pointTimeSec <= segment.end_time
        ) {
          return segment.emoji || null
        }
      }

      let nearest = null
      for (const segment of modeTimeline) {
        if (segment.start_time <= pointTimeSec) nearest = segment
      }
      if (nearest?.emoji) return nearest.emoji
    }

    return track.properties.dominant_mode_emoji || null
  }

  return null
}
