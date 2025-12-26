import { BaseLayer } from './base_layer'

/**
 * Family layer showing family member locations
 * Each member has unique color
 */
export class FamilyLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'family', ...options })
    this.memberColors = {}
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
      // Member circles
      {
        id: this.id,
        type: 'circle',
        source: this.sourceId,
        paint: {
          'circle-radius': 10,
          'circle-color': ['get', 'color'],
          'circle-stroke-width': 2,
          'circle-stroke-color': '#ffffff',
          'circle-opacity': 0.9
        }
      },

      // Member labels
      {
        id: `${this.id}-labels`,
        type: 'symbol',
        source: this.sourceId,
        layout: {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
          'text-size': 12,
          'text-offset': [0, 1.5],
          'text-anchor': 'top'
        },
        paint: {
          'text-color': '#111827',
          'text-halo-color': '#ffffff',
          'text-halo-width': 2
        }
      },

      // Pulse animation
      {
        id: `${this.id}-pulse`,
        type: 'circle',
        source: this.sourceId,
        paint: {
          'circle-radius': [
            'interpolate',
            ['linear'],
            ['zoom'],
            10, 15,
            15, 25
          ],
          'circle-color': ['get', 'color'],
          'circle-opacity': [
            'interpolate',
            ['linear'],
            ['get', 'lastUpdate'],
            Date.now() - 10000, 0,
            Date.now(), 0.3
          ]
        }
      }
    ]
  }

  getLayerIds() {
    return [this.id, `${this.id}-labels`, `${this.id}-pulse`]
  }

  /**
   * Update single family member location
   * @param {Object} member - { id, name, latitude, longitude, color }
   */
  updateMember(member) {
    const features = this.data?.features || []

    // Find existing or add new
    const index = features.findIndex(f => f.properties.id === member.id)

    const feature = {
      type: 'Feature',
      geometry: {
        type: 'Point',
        coordinates: [member.longitude, member.latitude]
      },
      properties: {
        id: member.id,
        name: member.name,
        color: member.color || this.getMemberColor(member.id),
        lastUpdate: Date.now()
      }
    }

    if (index >= 0) {
      features[index] = feature
    } else {
      features.push(feature)
    }

    this.update({
      type: 'FeatureCollection',
      features
    })
  }

  /**
   * Get consistent color for member
   */
  getMemberColor(memberId) {
    if (!this.memberColors[memberId]) {
      const colors = [
        '#3b82f6', '#10b981', '#f59e0b',
        '#ef4444', '#8b5cf6', '#ec4899'
      ]
      const index = Object.keys(this.memberColors).length % colors.length
      this.memberColors[memberId] = colors[index]
    }
    return this.memberColors[memberId]
  }

  /**
   * Remove family member
   */
  removeMember(memberId) {
    const features = this.data?.features || []
    const filtered = features.filter(f => f.properties.id !== memberId)

    this.update({
      type: 'FeatureCollection',
      features: filtered
    })
  }

  /**
   * Load all family members from API
   * @param {Object} locations - Array of family member locations
   */
  loadMembers(locations) {
    if (!Array.isArray(locations)) {
      console.warn('[FamilyLayer] Invalid locations data:', locations)
      return
    }

    const features = locations.map(location => ({
      type: 'Feature',
      geometry: {
        type: 'Point',
        coordinates: [location.longitude, location.latitude]
      },
      properties: {
        id: location.user_id,
        name: location.email || 'Unknown',
        email: location.email,
        color: location.color || this.getMemberColor(location.user_id),
        lastUpdate: Date.now(),
        battery: location.battery,
        batteryStatus: location.battery_status,
        updatedAt: location.updated_at
      }
    }))

    this.update({
      type: 'FeatureCollection',
      features
    })
  }

  /**
   * Center map on specific family member
   * @param {string} memberId - ID of the member to center on
   */
  centerOnMember(memberId) {
    const features = this.data?.features || []
    const member = features.find(f => f.properties.id === memberId)

    if (member && this.map) {
      this.map.flyTo({
        center: member.geometry.coordinates,
        zoom: 15,
        duration: 1500
      })
    }
  }

  /**
   * Get all current family members
   * @returns {Array} Array of member features
   */
  getMembers() {
    return this.data?.features || []
  }
}
