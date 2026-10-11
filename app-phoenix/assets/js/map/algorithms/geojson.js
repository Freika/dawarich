import { calculateDistance } from "./geometry.js"

export const SIMPLIFIED_POINTS_DISTANCE_METERS = 50

export function simplifyPointsForRendering(points) {
  if (!points.length) return points

  const simplified = [points[0]]
  let previousPoint = points[0]

  for (let i = 1; i < points.length; i++) {
    const point = points[i]
    const distance = calculateDistance(
      [previousPoint.longitude, previousPoint.latitude],
      [point.longitude, point.latitude],
    )

    if (distance >= SIMPLIFIED_POINTS_DISTANCE_METERS) {
      simplified.push(point)
      previousPoint = point
    }
  }

  return simplified
}

export function pointsToGeoJSON(points, options = {}) {
  const renderPoints = options.simplified
    ? simplifyPointsForRendering(points)
    : points

  return {
    type: "FeatureCollection",
    features: renderPoints.map((point) => ({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [point.longitude, point.latitude],
      },
      properties: {
        id: point.id,
        timestamp: point.timestamp,
        altitude: point.altitude,
        battery: point.battery,
        accuracy: point.accuracy,
        velocity: point.velocity,
        country_name: point.country_name,
        latitude: point.latitude,
        longitude: point.longitude,
      },
    })),
  }
}

export function formatTimestamp(timestamp, timezone = "UTC") {
  let date
  if (typeof timestamp === "string") {
    date = new Date(timestamp)
  } else if (timestamp < 10000000000) {
    date = new Date(timestamp * 1000)
  } else {
    date = new Date(timestamp)
  }

  return date.toLocaleString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
    timeZone: timezone,
  })
}

export function formatTimeOnly(timestamp, timezone = "UTC") {
  if (!timestamp) return "--:--"

  let date
  if (typeof timestamp === "string") {
    date = new Date(timestamp)
  } else if (timestamp < 10000000000) {
    date = new Date(timestamp * 1000)
  } else {
    date = new Date(timestamp)
  }

  return date.toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZone: timezone,
  })
}

export function escapeHtml(value) {
  if (value == null) return ""
  const str = String(value)
  const div = document.createElement("div")
  div.textContent = str
  return div.innerHTML
}

export function escapeAttribute(value) {
  return escapeHtml(value).replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}
