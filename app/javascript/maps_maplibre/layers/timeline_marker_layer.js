import { BaseLayer } from './base_layer'

/**
 * Timeline marker layer for displaying a pulsing marker at timeline position
 * Supports both circle markers (default) and transportation mode emojis
 * Uses orange color to distinguish from recent point (red)
 */
export class TimelineMarkerLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'timeline-marker', visible: false, ...options })
    this._markerMode = 'circle' // 'circle' or 'emoji'
    this._currentEmoji = null
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
      // Pulsing outer circle (always visible as background)
      {
        id: `${this.id}-pulse`,
        type: 'circle',
        source: this.sourceId,
        paint: {
          'circle-color': '#f97316', // Orange
          'circle-radius': [
            'interpolate',
            ['linear'],
            ['zoom'],
            0, 10,
            20, 50
          ],
          'circle-opacity': 0.3
        }
      },
      // Main point circle (hidden when showing emoji)
      {
        id: this.id,
        type: 'circle',
        source: this.sourceId,
        paint: {
          'circle-color': '#f97316', // Orange
          'circle-radius': [
            'interpolate',
            ['linear'],
            ['zoom'],
            0, 8,
            20, 24
          ],
          'circle-stroke-width': 3,
          'circle-stroke-color': '#ffffff'
        }
      },
      // Emoji symbol layer (hidden when showing circle)
      {
        id: `${this.id}-emoji`,
        type: 'symbol',
        source: this.sourceId,
        layout: {
          'text-field': ['get', 'emoji'],
          'text-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            0, 16,
            10, 24,
            20, 40
          ],
          'text-allow-overlap': true,
          'text-ignore-placement': true,
          'visibility': 'none'
        },
        paint: {
          'text-halo-color': '#ffffff',
          'text-halo-width': 2
        }
      }
    ]
  }

  /**
   * Set marker display mode
   * @param {string} mode - 'circle' or 'emoji'
   * @param {boolean} force - Force update even if mode hasn't changed
   * @private
   */
  _setMarkerMode(mode, force = false) {
    if (this._markerMode === mode && !force) return
    this._markerMode = mode

    if (!this.map) return

    const circleLayerId = this.id
    const emojiLayerId = `${this.id}-emoji`

    try {
      if (mode === 'emoji') {
        // Hide circle, show emoji
        if (this.map.getLayer(circleLayerId)) {
          this.map.setLayoutProperty(circleLayerId, 'visibility', 'none')
        }
        if (this.map.getLayer(emojiLayerId)) {
          this.map.setLayoutProperty(emojiLayerId, 'visibility', 'visible')
        }
      } else {
        // Show circle, hide emoji
        if (this.map.getLayer(circleLayerId)) {
          this.map.setLayoutProperty(circleLayerId, 'visibility', 'visible')
        }
        if (this.map.getLayer(emojiLayerId)) {
          this.map.setLayoutProperty(emojiLayerId, 'visibility', 'none')
        }
      }
    } catch (e) {
      // Layer might not exist yet, ignore
    }
  }

  /**
   * Show marker at specified coordinates
   * @param {number} lon - Longitude
   * @param {number} lat - Latitude
   * @param {Object} properties - Additional point properties (including emoji)
   */
  showMarker(lon, lat, properties = {}) {
    // Validate coordinates
    if (lon === undefined || lat === undefined || isNaN(lon) || isNaN(lat)) {
      console.warn('[TimelineMarker] Invalid coordinates:', lon, lat)
      return
    }

    // Determine marker mode based on emoji presence
    const emoji = properties.emoji
    const hasEmoji = emoji && typeof emoji === 'string' && emoji.trim() !== ''

    // Store emoji in properties for the symbol layer
    const featureProperties = { ...properties }
    if (hasEmoji) {
      featureProperties.emoji = emoji
    }

    const data = {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          geometry: {
            type: 'Point',
            coordinates: [lon, lat]
          },
          properties: featureProperties
        }
      ]
    }

    this.update(data)
    this._setMarkerMode(hasEmoji ? 'emoji' : 'circle')
    this._currentEmoji = hasEmoji ? emoji : null
    this.show()
  }

  /**
   * Get current emoji being displayed
   * @returns {string|null}
   */
  getCurrentEmoji() {
    return this._currentEmoji
  }

  /**
   * Hide the marker
   */
  hideMarker() {
    this.hide()
  }

  /**
   * Clear the marker data
   */
  clear() {
    this.update({
      type: 'FeatureCollection',
      features: []
    })
    this._currentEmoji = null
    this.hide()
  }

  /**
   * Override show to ensure correct layer visibility
   */
  show() {
    super.show()
    // Re-apply marker mode when showing (force update to ensure correct visibility)
    this._setMarkerMode(this._markerMode, true)
  }
}
