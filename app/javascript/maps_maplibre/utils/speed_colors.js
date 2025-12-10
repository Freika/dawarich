/**
 * Speed color utilities for route visualization
 * Provides speed calculation and color interpolation for route segments
 */

// Default color stops for speed visualization
export const colorStopsFallback = [
  { speed: 0, color: '#00ff00' },    // Stationary/very slow (green)
  { speed: 15, color: '#00ffff' },   // Walking/jogging (cyan)
  { speed: 30, color: '#ff00ff' },   // Cycling/slow driving (magenta)
  { speed: 50, color: '#ffff00' },   // Urban driving (yellow)
  { speed: 100, color: '#ff3300' }   // Highway driving (red)
]

/**
 * Encode color stops array to string format for storage
 * @param {Array} arr - Array of {speed, color} objects
 * @returns {string} Encoded string (e.g., "0:#00ff00|15:#00ffff")
 */
export function colorFormatEncode(arr) {
  return arr.map(item => `${item.speed}:${item.color}`).join('|')
}

/**
 * Decode color stops string to array format
 * @param {string} str - Encoded color stops string
 * @returns {Array} Array of {speed, color} objects
 */
export function colorFormatDecode(str) {
  return str.split('|').map(segment => {
    const [speed, color] = segment.split(':')
    return { speed: Number(speed), color }
  })
}

/**
 * Convert hex color to RGB object
 * @param {string} hex - Hex color (e.g., "#ff0000")
 * @returns {Object} RGB object {r, g, b}
 */
function hexToRGB(hex) {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return { r, g, b }
}

/**
 * Calculate speed between two points
 * @param {Object} point1 - First point with lat, lon, timestamp
 * @param {Object} point2 - Second point with lat, lon, timestamp
 * @returns {number} Speed in km/h
 */
export function calculateSpeed(point1, point2) {
  if (!point1 || !point2 || !point1.timestamp || !point2.timestamp) {
    return 0
  }

  const distanceKm = haversineDistance(
    point1.latitude, point1.longitude,
    point2.latitude, point2.longitude
  )
  const timeDiffSeconds = point2.timestamp - point1.timestamp

  // Handle edge cases
  if (timeDiffSeconds <= 0 || distanceKm <= 0) {
    return 0
  }

  const speedKmh = (distanceKm / timeDiffSeconds) * 3600

  // Cap speed at reasonable maximum (150 km/h)
  const MAX_SPEED = 150
  return Math.min(speedKmh, MAX_SPEED)
}

/**
 * Calculate haversine distance between two points
 * @param {number} lat1 - First point latitude
 * @param {number} lon1 - First point longitude
 * @param {number} lat2 - Second point latitude
 * @param {number} lon2 - Second point longitude
 * @returns {number} Distance in kilometers
 */
function haversineDistance(lat1, lon1, lat2, lon2) {
  const R = 6371 // Earth's radius in kilometers
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLon = (lon2 - lon1) * Math.PI / 180
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

/**
 * Get color for a given speed with interpolation
 * @param {number} speedKmh - Speed in km/h
 * @param {boolean} useSpeedColors - Whether to use speed-based coloring
 * @param {string} speedColorScale - Encoded color scale string
 * @returns {string} RGB color string (e.g., "rgb(255, 0, 0)")
 */
export function getSpeedColor(speedKmh, useSpeedColors, speedColorScale) {
  if (!useSpeedColors) {
    return '#0000ff' // Default blue color (matching v1)
  }

  let colorStops

  try {
    colorStops = colorFormatDecode(speedColorScale).map(stop => ({
      ...stop,
      rgb: hexToRGB(stop.color)
    }))
  } catch (error) {
    // If user has given invalid values, use fallback
    colorStops = colorStopsFallback.map(stop => ({
      ...stop,
      rgb: hexToRGB(stop.color)
    }))
  }

  // Find the appropriate color segment and interpolate
  for (let i = 1; i < colorStops.length; i++) {
    if (speedKmh <= colorStops[i].speed) {
      const ratio = (speedKmh - colorStops[i-1].speed) / (colorStops[i].speed - colorStops[i-1].speed)
      const color1 = colorStops[i-1].rgb
      const color2 = colorStops[i].rgb

      const r = Math.round(color1.r + (color2.r - color1.r) * ratio)
      const g = Math.round(color1.g + (color2.g - color1.g) * ratio)
      const b = Math.round(color1.b + (color2.b - color1.b) * ratio)

      return `rgb(${r}, ${g}, ${b})`
    }
  }

  // If speed exceeds all stops, return the last color
  return colorStops[colorStops.length - 1].color
}
