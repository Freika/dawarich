import { BaseLayer } from './base_layer'

/**
 * Routes layer showing travel paths
 * Connects points chronologically with solid color
 */
export class RoutesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'routes', ...options })
    this.maxGapHours = options.maxGapHours || 5 // Max hours between points to connect
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      }
    }
  }

  getLayerConfigs() {
    return [
      {
        id: this.id,
        type: 'line',
        source: this.sourceId,
        layout: {
          'line-join': 'round',
          'line-cap': 'round'
        },
        paint: {
          'line-color': '#f97316',  // Solid orange color
          'line-width': 3,
          'line-opacity': 0.8
        }
      }
    ]
  }

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
   * Convert points to route LineStrings with splitting
   * Matches V1's route splitting logic for consistency
   * @param {Array} points - Points from API
   * @param {Object} options - Splitting options
   * @returns {Object} GeoJSON FeatureCollection
   */
  static pointsToRoutes(points, options = {}) {
    if (points.length < 2) {
      return { type: 'FeatureCollection', features: [] }
    }

    // Default thresholds (matching V1 defaults from polylines.js)
    const distanceThresholdKm = (options.distanceThresholdMeters || 500) / 1000
    const timeThresholdMinutes = options.timeThresholdMinutes || 60

    // Sort by timestamp
    const sorted = points.slice().sort((a, b) => a.timestamp - b.timestamp)

    // Split into segments based on distance and time gaps (like V1)
    const segments = []
    let currentSegment = [sorted[0]]

    for (let i = 1; i < sorted.length; i++) {
      const prev = sorted[i - 1]
      const curr = sorted[i]

      // Calculate distance between consecutive points
      const distance = this.haversineDistance(
        prev.latitude, prev.longitude,
        curr.latitude, curr.longitude
      )

      // Calculate time difference in minutes
      const timeDiff = (curr.timestamp - prev.timestamp) / 60

      // Split if either threshold is exceeded (matching V1 logic)
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

    // Convert segments to LineStrings
    const features = segments.map(segment => {
      const coordinates = segment.map(p => [p.longitude, p.latitude])

      // Calculate total distance for the segment
      let totalDistance = 0
      for (let i = 0; i < segment.length - 1; i++) {
        totalDistance += this.haversineDistance(
          segment[i].latitude, segment[i].longitude,
          segment[i + 1].latitude, segment[i + 1].longitude
        )
      }

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
    })

    return {
      type: 'FeatureCollection',
      features
    }
  }
}
