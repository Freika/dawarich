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
   * Calculates the interpolated latitude for a given longitude on a Great Circle path.
   * Unlike linear interpolation, this accounts for the Earth's spherical shape.
   * @param {number} lat1 - Latitude of the first point.
   * @param {number} lon1 - Longitude of the first point.
   * @param {number} lat2 - Latitude of the second point.
   * @param {number} lon2 - Longitude of the second point.
   * @param {number} interpLon - The longitude at which to find the latitude.
   * @returns {number|null} - The interpolated latitude or null if inputs are invalid.
   */
  static getInterpolatedLat(lat1, lon1, lat2, lon2, interpLon) {
    const nLat1 = Number(lat1)
    const nLon1 = Number(lon1)
    const nLat2 = Number(lat2)
    const nLon2 = Number(lon2)
    const nInterpLon = Number(interpLon)

    if ([nLat1, nLon1, nLat2, nLon2, nInterpLon].some(Number.isNaN)) {
      return null
    }

    // Same longitude — can't interpolate latitude based on longitude
    if (Math.abs(nLon1 - nLon2) < 0.0000001) {
      return nLat1
    }

    const toRad = (deg) => (deg * Math.PI) / 180
    const toDeg = (rad) => (rad * 180) / Math.PI

    const φ1 = toRad(nLat1)
    const λ1 = toRad(nLon1)
    const φ2 = toRad(nLat2)
    const λ2 = toRad(nLon2)
    const λ3 = toRad(nInterpLon)

    // Spherical interpolation: intersection of great circle and meridian
    // tan(φ) = [tan(φ1) * sin(λ2 - λ3) + tan(φ2) * sin(λ3 - λ1)] / sin(λ2 - λ1)
    const sinDeltaL = Math.sin(λ2 - λ1)
    const term1 = Math.tan(φ1) * Math.sin(λ2 - λ3)
    const term2 = Math.tan(φ2) * Math.sin(λ3 - λ1)
    const tanPhi = (term1 + term2) / sinDeltaL
    const result = toDeg(Math.atan(tanPhi))

    return Number.isFinite(result) ? result : null
  }

  /**
   * Detects indices where the path crosses the International Date Line.
   * @param {Array<Object>} coords - Array of objects with 'latitude' and 'longitude' properties.
   * @returns {Array<number>} Indices of the elements that represent the start of a crossing.
   */
  static findIDLCrossings(coords) {
    const crossings = [0]

    for (let i = 0; i < coords.length - 1; i++) {
      const currentLng = parseFloat(coords[i].longitude)
      const nextLng = parseFloat(coords[i + 1].longitude)

      if (Number.isNaN(currentLng) || Number.isNaN(nextLng)) continue

      // A jump of more than 180 degrees indicates a wrap-around
      if (Math.abs(currentLng - nextLng) > 180) {
        crossings.push(i + 1)
      }
    }
    crossings.push(coords.length)

    return crossings
  }

  /**
   * Unwrap coordinates to handle International Date Line (IDL) crossings
   * This ensures routes draw the short way across IDL instead of wrapping around globe
   * @param {Array} segment - Array of points with longitude and latitude properties
   * @returns {Array<Array<[number, number]>>} Always returns an array of coordinate arrays (MultiLineString-compatible)
   */
  static unwrapCoordinates(segment) {
    const crossingIndices = RouteSegmenter.findIDLCrossings(segment)
    const coordsList = []

    for (let i = 0; i < crossingIndices.length - 1; i++) {
      const subsegment = segment.slice(
        crossingIndices[i],
        crossingIndices[i + 1],
      )
      const coords = subsegment.map((p) => [
        parseFloat(p.longitude),
        parseFloat(p.latitude),
      ])
      coordsList.push(coords)
    }

    if (coordsList.length > 1) {
      // Stitch segments at ±180° with interpolated latitude for seamless rendering
      for (let i = 0; i < coordsList.length - 1; i++) {
        const lastPoint = coordsList[i].at(-1)
        const nextPoint = coordsList[i + 1][0]
        const interpLat = RouteSegmenter.getInterpolatedLat(
          lastPoint[1],
          lastPoint[0],
          nextPoint[1],
          nextPoint[0],
          180,
        )
        const safeInterpLat = Number.isFinite(interpLat)
          ? interpLat
          : lastPoint[1]
        coordsList[i].push([180 * Math.sign(lastPoint[0]), safeInterpLat])
        coordsList[i + 1].unshift([
          180 * Math.sign(nextPoint[0]),
          safeInterpLat,
        ])
      }
    }

    // Always return array-of-arrays for consistent MultiLineString-compatible type
    return coordsList
  }

  /**
   * True if the segment prev→curr passes within `radiusMeters` of any zone center.
   * Uses an equirectangular planar approximation (zones are small, ≤5km).
   * @param {Object} prev - point with latitude/longitude
   * @param {Object} curr - point with latitude/longitude
   * @param {Array} zones - [{ lon, lat, radiusMeters }]
   */
  static segmentCrossesZone(prev, curr, zones) {
    if (!zones || zones.length === 0) return false

    const R = 6371000
    const toRad = (d) => (d * Math.PI) / 180
    const project = (lat, lon, lat0) => ({
      x: R * toRad(lon) * Math.cos(toRad(lat0)),
      y: R * toRad(lat),
    })

    return zones.some((zone) => {
      const lat0 = zone.lat
      const a = project(Number(prev.latitude), Number(prev.longitude), lat0)
      const b = project(Number(curr.latitude), Number(curr.longitude), lat0)
      const c = project(zone.lat, zone.lon, lat0)

      const dx = b.x - a.x
      const dy = b.y - a.y
      const lenSq = dx * dx + dy * dy
      let t = lenSq === 0 ? 0 : ((c.x - a.x) * dx + (c.y - a.y) * dy) / lenSq
      t = Math.max(0, Math.min(1, t))
      const px = a.x + t * dx
      const py = a.y + t * dy
      const dist = Math.hypot(c.x - px, c.y - py)

      return dist <= zone.radiusMeters
    })
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
      const distance = RouteSegmenter.haversineDistance(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      )

      // Calculate time difference in minutes
      const timeDiff = (curr.timestamp - prev.timestamp) / 60

      const crossesZone = RouteSegmenter.segmentCrossesZone(
        prev,
        curr,
        options.privacyZones,
      )

      // Split if any threshold is exceeded
      if (
        distance > distanceThresholdKm ||
        timeDiff > timeThresholdMinutes ||
        crossesZone
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

    const features = Object.values(buckets).flatMap((bucket) => {
      if (bucket.length < 2) return []
      const sorted = bucket.slice().sort((a, b) => a.timestamp - b.timestamp)
      const segments = RouteSegmenter.splitIntoSegments(sorted, {
        distanceThresholdKm,
        timeThresholdMinutes,
        privacyZones: options.privacyZones,
      })
      return segments.map((segment) => RouteSegmenter.segmentToFeature(segment))
    })

    return {
      type: "FeatureCollection",
      features,
    }
  }
}
