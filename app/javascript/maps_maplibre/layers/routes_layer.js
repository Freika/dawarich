import { BaseLayer } from './base_layer'

/**
 * Routes layer showing travel paths
 * Connects points chronologically with solid color
 */
export class RoutesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'routes', ...options })
    this.maxGapHours = options.maxGapHours || 5 // Max hours between points to connect
    this.hoverSourceId = 'routes-hover-source'
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

  /**
   * Override add() to create both main and hover sources
   */
  add(data) {
    this.data = data

    // Add main source
    if (!this.map.getSource(this.sourceId)) {
      this.map.addSource(this.sourceId, this.getSourceConfig())
    }

    // Add hover source (initially empty)
    if (!this.map.getSource(this.hoverSourceId)) {
      this.map.addSource(this.hoverSourceId, {
        type: 'geojson',
        data: { type: 'FeatureCollection', features: [] }
      })
    }

    // Add layers
    const layers = this.getLayerConfigs()
    layers.forEach(layerConfig => {
      if (!this.map.getLayer(layerConfig.id)) {
        this.map.addLayer(layerConfig)
      }
    })

    this.setVisibility(this.visible)
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
          // Use color from feature properties if available, otherwise default blue
          'line-color': [
            'case',
            ['has', 'color'],
            ['get', 'color'],
            '#0000ff'  // Default blue color (matching v1)
          ],
          'line-width': 3,
          'line-opacity': 0.8
        }
      },
      {
        id: 'routes-hover',
        type: 'line',
        source: this.hoverSourceId,
        layout: {
          'line-join': 'round',
          'line-cap': 'round'
        },
        paint: {
          'line-color': '#ffff00',  // Yellow highlight
          'line-width': 8,
          'line-opacity': 1.0
        }
      }
      // Note: routes-hit layer is added separately in LayerManager after points layer
      // for better interactivity (see _addRoutesHitLayer method)
    ]
  }

  /**
   * Override setVisibility to also control routes-hit layer
   * @param {boolean} visible - Show/hide layer
   */
  setVisibility(visible) {
    // Call parent to handle main routes and routes-hover layers
    super.setVisibility(visible)

    // Also control routes-hit layer if it exists
    if (this.map.getLayer('routes-hit')) {
      const visibility = visible ? 'visible' : 'none'
      this.map.setLayoutProperty('routes-hit', 'visibility', visibility)
    }
  }

  /**
   * Update hover layer with route geometry
   * @param {Object|null} feature - Route feature, FeatureCollection, or null to clear
   */
  setHoverRoute(feature) {
    const hoverSource = this.map.getSource(this.hoverSourceId)
    if (!hoverSource) return

    if (feature) {
      // Handle both single feature and FeatureCollection
      if (feature.type === 'FeatureCollection') {
        hoverSource.setData(feature)
      } else {
        hoverSource.setData({
          type: 'FeatureCollection',
          features: [feature]
        })
      }
    } else {
      hoverSource.setData({ type: 'FeatureCollection', features: [] })
    }
  }

  /**
   * Override remove() to clean up hover source and hit layer
   */
  remove() {
    // Remove layers
    this.getLayerIds().forEach(layerId => {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId)
      }
    })

    // Remove routes-hit layer if it exists
    if (this.map.getLayer('routes-hit')) {
      this.map.removeLayer('routes-hit')
    }

    // Remove main source
    if (this.map.getSource(this.sourceId)) {
      this.map.removeSource(this.sourceId)
    }

    // Remove hover source
    if (this.map.getSource(this.hoverSourceId)) {
      this.map.removeSource(this.hoverSourceId)
    }

    this.data = null
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
   * Also handles International Date Line (IDL) crossings
   * @param {Array} points - Points from API
   * @param {Object} options - Splitting options
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

    // Convert segments to LineStrings
    const features = segments.map(segment => {
      // Unwrap coordinates to handle International Date Line (IDL) crossings
      // This ensures routes draw the short way across IDL instead of wrapping around globe
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
            // Subtract 360° to make it continuous (e.g., 170° to -170° becomes 170° to -170°-360° = -530°)
            offset -= 360
            lon -= 360
          } else if (lonDiff < -180) {
            // Crossed from west to east (e.g., -170° to 170°)
            // Add 360° to make it continuous (e.g., -170° to 170° becomes -170° to 170°+360° = 530°)
            offset += 360
            lon += 360
          }
        }

        coordinates.push([lon, point.latitude])
      }

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
