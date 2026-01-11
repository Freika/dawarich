/**
 * RouteSegmenter - Utility for converting points into route segments
 * Handles route splitting based on time/distance thresholds and IDL crossings
 */
export class RouteSegmenter {
  /**
   * Calculate haversine distance between two points in kilometers
   * @param {number} lat1 - First point latitude
   * @param {number} lon1 - First point longitude
   * @param {number} lat2 - Second point latitude
   * @param {number} lon2 - Second point longitude
   * @returns {number} Distance in kilometers
   */
  static haversineDistance(lat1, lon1, lat2, lon2) {
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
   * Unwrap coordinates to handle International Date Line (IDL) crossings
   * This ensures routes draw the short way across IDL instead of wrapping around globe
   * @param {Array} segment - Array of points with longitude and latitude properties
   * @returns {Array} Array of [lon, lat] coordinate pairs with IDL unwrapping applied
   */
  static unwrapCoordinates(segment) {
    const coordinates = []
    let offset = 0 // Cumulative longitude offset for unwrapping

    for (let i = 0; i < segment.length; i++) {
      const point = segment[i]
      let lon = point.longitude + offset

      // Check for IDL crossing between consecutive points
      if (i > 0) {
        const prevLon = coordinates[i - 1][0]
        const lonDiff = lon - prevLon

        // If longitude jumps more than 180°, we crossed the IDL
        if (lonDiff > 180) {
          // Crossed from east to west (e.g., 170° to -170°)
          // Subtract 360° to make it continuous
          offset -= 360
          lon -= 360
        } else if (lonDiff < -180) {
          // Crossed from west to east (e.g., -170° to 170°)
          // Add 360° to make it continuous
          offset += 360
          lon += 360
        }
      }

      coordinates.push([lon, point.latitude])
    }

    return coordinates
  }

  /**
   * Calculate total distance for a segment
   * @param {Array} segment - Array of points
   * @returns {number} Total distance in kilometers
   */
  static calculateSegmentDistance(segment) {
    let totalDistance = 0
    for (let i = 0; i < segment.length - 1; i++) {
      totalDistance += this.haversineDistance(
        segment[i].latitude, segment[i].longitude,
        segment[i + 1].latitude, segment[i + 1].longitude
      )
    }
    return totalDistance
  }

  /**
   * Split points into segments based on distance and time gaps
   * @param {Array} points - Sorted array of points
   * @param {Object} options - Splitting options
   * @param {number} options.distanceThresholdKm - Distance threshold in km
   * @param {number} options.timeThresholdMinutes - Time threshold in minutes
   * @returns {Array} Array of segments
   */
  static splitIntoSegments(points, options) {
    const { distanceThresholdKm, timeThresholdMinutes } = options

    const segments = []
    let currentSegment = [points[0]]

    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1]
      const curr = points[i]

      // Calculate distance between consecutive points
      const distance = this.haversineDistance(
        prev.latitude, prev.longitude,
        curr.latitude, curr.longitude
      )

      // Calculate time difference in minutes
      const timeDiff = (curr.timestamp - prev.timestamp) / 60

      // Split if any threshold is exceeded
      if (distance > distanceThresholdKm || timeDiff > timeThresholdMinutes) {
        if (currentSegment.length > 1) {
          segments.push(currentSegment)
        }
        currentSegment = [curr]
      } else {
        currentSegment.push(curr)
      }
    }

    if (currentSegment.length > 1) {
      segments.push(currentSegment)
    }

    return segments
  }

  /**
   * Convert a segment to a GeoJSON LineString feature
   * @param {Array} segment - Array of points
   * @returns {Object} GeoJSON Feature
   */
  static segmentToFeature(segment) {
    const coordinates = this.unwrapCoordinates(segment)
    const totalDistance = this.calculateSegmentDistance(segment)

    return {
      type: 'Feature',
      geometry: {
        type: 'LineString',
        coordinates
      },
      properties: {
        pointCount: segment.length,
        startTime: segment[0].timestamp,
        endTime: segment[segment.length - 1].timestamp,
        distance: totalDistance
      }
    }
  }

  /**
   * Convert points to route LineStrings with splitting
   * Matches V1's route splitting logic for consistency
   * Also handles International Date Line (IDL) crossings
   * @param {Array} points - Points from API
   * @param {Object} options - Splitting options
   * @param {number} options.distanceThresholdMeters - Distance threshold in meters (note: unit mismatch preserved for V1 compat)
   * @param {number} options.timeThresholdMinutes - Time threshold in minutes
   * @returns {Object} GeoJSON FeatureCollection
   */
  static pointsToRoutes(points, options = {}) {
    if (points.length < 2) {
      return { type: 'FeatureCollection', features: [] }
    }

    // Default thresholds (matching V1 defaults from polylines.js)
    // Note: V1 has a unit mismatch bug where it compares km to meters directly
    // We replicate this behavior for consistency with V1
    const distanceThresholdKm = options.distanceThresholdMeters || 500
    const timeThresholdMinutes = options.timeThresholdMinutes || 60

    // Sort by timestamp
    const sorted = points.slice().sort((a, b) => a.timestamp - b.timestamp)

    // Split into segments based on distance and time gaps
    const segments = this.splitIntoSegments(sorted, {
      distanceThresholdKm,
      timeThresholdMinutes
    })

    // Convert segments to LineStrings
    const features = segments.map(segment => this.segmentToFeature(segment))

    return {
      type: 'FeatureCollection',
      features
    }
  }
}
