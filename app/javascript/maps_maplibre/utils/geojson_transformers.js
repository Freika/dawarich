/**
 * Transform points array to GeoJSON FeatureCollection
 * @param {Array} points - Array of point objects from API
 * @returns {Object} GeoJSON FeatureCollection
 */
export function pointsToGeoJSON(points) {
  return {
    type: 'FeatureCollection',
    features: points.map(point => ({
      type: 'Feature',
      geometry: {
        type: 'Point',
        coordinates: [point.longitude, point.latitude]
      },
      properties: {
        id: point.id,
        timestamp: point.timestamp,
        altitude: point.altitude,
        battery: point.battery,
        accuracy: point.accuracy,
        velocity: point.velocity,
        country_name: point.country_name
      }
    }))
  }
}

/**
 * Format timestamp for display
 * @param {number|string} timestamp - Unix timestamp (seconds) or ISO 8601 string
 * @returns {string} Formatted date/time
 */
export function formatTimestamp(timestamp) {
  // Handle different timestamp formats
  let date
  if (typeof timestamp === 'string') {
    // ISO 8601 string
    date = new Date(timestamp)
  } else if (timestamp < 10000000000) {
    // Unix timestamp in seconds
    date = new Date(timestamp * 1000)
  } else {
    // Unix timestamp in milliseconds
    date = new Date(timestamp)
  }

  return date.toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}
