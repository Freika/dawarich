import { greatCircleLines } from "./flight_arcs"

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
    const dLat = ((lat2 - lat1) * Math.PI) / 180
    const dLon = ((lon2 - lon1) * Math.PI) / 180
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2)
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    return R * c
  }

  /**
   * Unwrap coordinates to handle International Date Line (IDL) crossings
   * This ensures routes draw the short way across IDL instead of wrapping around globe
   * @param {Array} segment - Array of points with longitude and latitude properties
   * @returns {Array<Array<[number, number]>>} Always returns an array of coordinate arrays (MultiLineString-compatible)
   */
  static unwrapCoordinates(segment) {
    const lines = greatCircleLines(
      segment.map((p) => [parseFloat(p.longitude), parseFloat(p.latitude)]),
    )
    return lines.flatMap((line) =>
      RouteSegmenter.stitchAntimeridian(
        line.map(([longitude, latitude]) => ({ longitude, latitude })),
      ),
    )
  }

  static stitchAntimeridian(points) {
    const coordinates = points.map((point) => [
      parseFloat(point.longitude),
      parseFloat(point.latitude),
    ])
    // Keep each vertex in the world copy nearest the preceding vertex.
    // Artificial seam vertices can introduce long edges and unstable polar interpolation.
    for (let i = 1; i < coordinates.length; i++) {
      while (coordinates[i][0] - coordinates[i - 1][0] > 180)
        coordinates[i][0] -= 360
      while (coordinates[i][0] - coordinates[i - 1][0] < -180)
        coordinates[i][0] += 360
    }
    return [coordinates]
  }

  /**
   * Calculate total distance for a segment
   * @param {Array} segment - Array of points
   * @returns {number} Total distance in kilometers
   */
  static calculateSegmentDistance(segment) {
    let totalDistance = 0
    for (let i = 0; i < segment.length - 1; i++) {
      totalDistance += RouteSegmenter.haversineDistance(
        segment[i].latitude,
        segment[i].longitude,
        segment[i + 1].latitude,
        segment[i + 1].longitude,
      )
    }
    return totalDistance
  }

  /**
   * True if the segment prev→curr passes within a zone's radius of its center.
   * Uses an equirectangular projection around each zone (zones are small).
   * @param {Object} prev - point with latitude/longitude
   * @param {Object} curr - point with latitude/longitude
   * @param {Array} zones - [{ lon, lat, radiusMeters }]
   */
  static segmentCrossesZone(prev, curr, zones) {
    if (!zones?.length) return false

    const R = 6371000
    const toRad = (d) => (d * Math.PI) / 180

    return zones.some((zone) => {
      const cosLat = Math.cos(toRad(zone.lat))
      const project = (lat, lon) => ({
        x: R * toRad(Number(lon) - zone.lon) * cosLat,
        y: R * toRad(Number(lat) - zone.lat),
      })
      const a = project(prev.latitude, prev.longitude)
      const b = project(curr.latitude, curr.longitude)
      const dx = b.x - a.x
      const dy = b.y - a.y
      const lenSq = dx * dx + dy * dy
      const t =
        lenSq === 0
          ? 0
          : Math.max(0, Math.min(1, -(a.x * dx + a.y * dy) / lenSq))

      return Math.hypot(a.x + t * dx, a.y + t * dy) <= zone.radiusMeters
    })
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
    const { distanceThresholdKm, timeThresholdMinutes, privacyZones } = options

    const segments = []
    let currentSegment = [points[0]]

    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1]
      const curr = points[i]

      // Calculate distance between consecutive points
      const distance = RouteSegmenter.haversineDistance(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      )

      // Calculate time difference in minutes
      const timeDiff = (curr.timestamp - prev.timestamp) / 60

      // Split if any threshold is exceeded
      if (
        distance > distanceThresholdKm ||
        timeDiff > timeThresholdMinutes ||
        RouteSegmenter.segmentCrossesZone(prev, curr, privacyZones)
      ) {
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
   * Convert a segment to a GeoJSON LineString (or MultiLineString if the IDL is crossed) feature
   * @param {Array} segment - Array of points
   * @returns {Object} GeoJSON Feature
   */
  static segmentToFeature(segment) {
    const coordinates = RouteSegmenter.unwrapCoordinates(segment)
    if (coordinates.length === 0) return null
    const totalDistance = RouteSegmenter.calculateSegmentDistance(segment)

    const startTime = segment[0].timestamp
    const endTime = segment[segment.length - 1].timestamp

    // Generate a stable, unique route ID based on start/end times
    const routeId = `route-${startTime}-${endTime}`

    // unwrapCoordinates always returns array-of-arrays; use LineString for single segments
    const isMultiPath = coordinates.length > 1

    return {
      type: "Feature",
      geometry: {
        type: isMultiPath ? "MultiLineString" : "LineString",
        coordinates: isMultiPath ? coordinates : coordinates[0],
      },
      properties: {
        id: routeId,
        pointCount: isMultiPath ? coordinates.flat().length : segment.length,
        startTime,
        endTime,
        distance: totalDistance,
      },
    }
  }

  /**
   * Cut a segment wherever another tracker's segment fits entirely inside one
   * of its gaps, mirroring Tracks::HandoffSplitter on the server
   * @param {Array} segment - Sorted points of one tracker
   * @param {Array} otherSegments - Segments of the other trackers
   * @returns {Array} Array of segments
   */
  static splitAtHandoffs(segment, otherSegments) {
    const cuts = new Set()
    for (const other of otherSegments) {
      const start = other[0].timestamp
      const end = other[other.length - 1].timestamp
      let index = 0
      let high = segment.length
      while (index < high) {
        const mid = (index + high) >> 1
        if (segment[mid].timestamp < start) index = mid + 1
        else high = mid
      }
      if (index > 0 && index < segment.length && segment[index].timestamp > end)
        cuts.add(index)
    }
    if (cuts.size === 0) return [segment]

    const bounds = [0, ...[...cuts].sort((a, b) => a - b), segment.length]
    return bounds
      .slice(1)
      .map((to, i) => segment.slice(bounds[i], to))
      .filter((piece) => piece.length > 1)
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
      return { type: "FeatureCollection", features: [] }
    }

    // Default thresholds (matching V1 defaults from polylines.js)
    // Note: V1 has a unit mismatch bug where it compares km to meters directly
    // We replicate this behavior for consistency with V1
    const distanceThresholdKm = options.distanceThresholdMeters || 500
    const timeThresholdMinutes = options.timeThresholdMinutes || 60

    const buckets = points.reduce((acc, p) => {
      const key = p.tracker_id || ""
      if (!acc[key]) acc[key] = []
      acc[key].push(p)
      return acc
    }, {})

    const segmentsByTracker = Object.values(buckets).map((bucket) => {
      if (bucket.length < 2) return []
      const sorted = bucket.slice().sort((a, b) => a.timestamp - b.timestamp)
      return RouteSegmenter.splitIntoSegments(sorted, {
        distanceThresholdKm,
        timeThresholdMinutes,
        privacyZones: options.privacyZones,
      })
    })

    const features = segmentsByTracker.flatMap((segments, index) => {
      const otherSegments = segmentsByTracker
        .filter((_, otherIndex) => otherIndex !== index)
        .flat()
      return segments
        .flatMap((segment) =>
          RouteSegmenter.splitAtHandoffs(segment, otherSegments),
        )
        .map((segment) => RouteSegmenter.segmentToFeature(segment))
        .filter(Boolean)
    })

    return {
      type: "FeatureCollection",
      features,
    }
  }
}
