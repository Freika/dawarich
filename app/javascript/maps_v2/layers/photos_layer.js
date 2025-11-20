import { BaseLayer } from './base_layer'

/**
 * Photos layer with thumbnail markers
 * Uses circular image markers loaded from photo thumbnails
 */
export class PhotosLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'photos', ...options })
    this.loadedImages = new Set()
  }

  async add(data) {
    // Load thumbnail images before adding layer
    await this.loadThumbnailImages(data)
    super.add(data)
  }

  async update(data) {
    await this.loadThumbnailImages(data)
    super.update(data)
  }

  /**
   * Load thumbnail images into map
   * @param {Object} geojson - GeoJSON with photo features
   */
  async loadThumbnailImages(geojson) {
    if (!geojson?.features) return

    const imagePromises = geojson.features.map(async (feature) => {
      const photoId = feature.properties.id
      const thumbnailUrl = feature.properties.thumbnail_url
      const imageId = `photo-${photoId}`

      // Skip if already loaded
      if (this.loadedImages.has(imageId) || this.map.hasImage(imageId)) {
        return
      }

      try {
        await this.loadImageToMap(imageId, thumbnailUrl)
        this.loadedImages.add(imageId)
      } catch (error) {
        console.warn(`Failed to load photo thumbnail ${photoId}:`, error)
      }
    })

    await Promise.all(imagePromises)
  }

  /**
   * Load image into MapLibre
   * @param {string} imageId - Unique image identifier
   * @param {string} url - Image URL
   */
  async loadImageToMap(imageId, url) {
    return new Promise((resolve, reject) => {
      this.map.loadImage(url, (error, image) => {
        if (error) {
          reject(error)
          return
        }

        // Add image if not already added
        if (!this.map.hasImage(imageId)) {
          this.map.addImage(imageId, image)
        }
        resolve()
      })
    })
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
      // Photo thumbnail background circle
      {
        id: `${this.id}-background`,
        type: 'circle',
        source: this.sourceId,
        paint: {
          'circle-radius': 22,
          'circle-color': '#ffffff',
          'circle-stroke-width': 2,
          'circle-stroke-color': '#3b82f6'
        }
      },

      // Photo thumbnail images
      {
        id: this.id,
        type: 'symbol',
        source: this.sourceId,
        layout: {
          'icon-image': ['concat', 'photo-', ['get', 'id']],
          'icon-size': 0.15, // Scale down thumbnails
          'icon-allow-overlap': true,
          'icon-ignore-placement': true
        }
      }
    ]
  }

  getLayerIds() {
    return [`${this.id}-background`, this.id]
  }

  /**
   * Clean up loaded images when layer is removed
   */
  remove() {
    super.remove()
    // Note: We don't remove images from map as they might be reused
  }
}
