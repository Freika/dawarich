import { SettingsManager } from 'maps_maplibre/utils/settings_manager'
import { Toast } from 'maps_maplibre/components/toast'
import { lazyLoader } from 'maps_maplibre/utils/lazy_loader'

/**
 * Manages routes-related operations for Maps V2
 * Including speed-colored routes, route generation, and layer management
 */
export class RoutesManager {
  constructor(controller) {
    this.controller = controller
    this.map = controller.map
    this.layerManager = controller.layerManager
    this.settings = controller.settings
  }

  /**
   * Toggle routes layer visibility
   */
  toggleRoutes(event) {
    const element = event.currentTarget
    const visible = element.checked

    const routesLayer = this.layerManager.getLayer('routes')
    if (routesLayer) {
      routesLayer.toggle(visible)
    }

    if (this.controller.hasRoutesOptionsTarget) {
      this.controller.routesOptionsTarget.style.display = visible ? 'block' : 'none'
    }

    SettingsManager.updateSetting('routesVisible', visible)
  }

  /**
   * Toggle speed-colored routes
   */
  async toggleSpeedColoredRoutes(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('speedColoredRoutesEnabled', enabled)

    if (this.controller.hasSpeedColorScaleContainerTarget) {
      this.controller.speedColorScaleContainerTarget.classList.toggle('hidden', !enabled)
    }

    await this.reloadRoutes()
  }

  /**
   * Open speed color editor modal
   */
  openSpeedColorEditor() {
    const currentScale = this.controller.speedColorScaleInputTarget.value ||
      '0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300'

    let modal = document.getElementById('speed-color-editor-modal')
    if (!modal) {
      modal = this.createSpeedColorEditorModal(currentScale)
      document.body.appendChild(modal)
    } else {
      const controller = this.controller.application.getControllerForElementAndIdentifier(modal, 'speed-color-editor')
      if (controller) {
        controller.colorStopsValue = currentScale
        controller.loadColorStops()
      }
    }

    const checkbox = modal.querySelector('.modal-toggle')
    if (checkbox) {
      checkbox.checked = true
    }
  }

  /**
   * Create speed color editor modal element
   */
  createSpeedColorEditorModal(currentScale) {
    const modal = document.createElement('div')
    modal.id = 'speed-color-editor-modal'
    modal.setAttribute('data-controller', 'speed-color-editor')
    modal.setAttribute('data-speed-color-editor-color-stops-value', currentScale)
    modal.setAttribute('data-action', 'speed-color-editor:save->maps-v2#handleSpeedColorSave')

    modal.innerHTML = `
      <input type="checkbox" id="speed-color-editor-toggle" class="modal-toggle" />
      <div class="modal" role="dialog" data-speed-color-editor-target="modal">
        <div class="modal-box max-w-2xl">
          <h3 class="text-lg font-bold mb-4">Edit Speed Color Gradient</h3>

          <div class="space-y-4">
            <!-- Gradient Preview -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Preview</span>
              </label>
              <div class="h-12 rounded-lg border-2 border-base-300"
                   data-speed-color-editor-target="preview"></div>
              <label class="label">
                <span class="label-text-alt">This gradient will be applied to routes based on speed</span>
              </label>
            </div>

            <!-- Color Stops List -->
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Color Stops</span>
              </label>
              <div class="space-y-2" data-speed-color-editor-target="stopsList"></div>
            </div>

            <!-- Add Stop Button -->
            <button type="button"
                    class="btn btn-sm btn-outline w-full"
                    data-action="click->speed-color-editor#addStop">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
              </svg>
              Add Color Stop
            </button>
          </div>

          <div class="modal-action">
            <button type="button"
                    class="btn btn-ghost"
                    data-action="click->speed-color-editor#resetToDefault">
              Reset to Default
            </button>
            <button type="button"
                    class="btn"
                    data-action="click->speed-color-editor#close">
              Cancel
            </button>
            <button type="button"
                    class="btn btn-primary"
                    data-action="click->speed-color-editor#save">
              Save
            </button>
          </div>
        </div>
        <label class="modal-backdrop" for="speed-color-editor-toggle"></label>
      </div>
    `

    return modal
  }

  /**
   * Handle speed color save event from editor
   */
  handleSpeedColorSave(event) {
    const newScale = event.detail.colorStops

    this.controller.speedColorScaleInputTarget.value = newScale
    SettingsManager.updateSetting('speedColorScale', newScale)

    if (this.controller.speedColoredToggleTarget.checked) {
      this.reloadRoutes()
    }
  }

  /**
   * Reload routes layer
   */
  async reloadRoutes() {
    this.controller.showLoading('Reloading routes...')

    try {
      const pointsLayer = this.layerManager.getLayer('points')
      const points = pointsLayer?.data?.features?.map(f => ({
        latitude: f.geometry.coordinates[1],
        longitude: f.geometry.coordinates[0],
        timestamp: f.properties.timestamp
      })) || []

      const distanceThresholdMeters = this.settings.metersBetweenRoutes || 500
      const timeThresholdMinutes = this.settings.minutesBetweenRoutes || 60

      const { calculateSpeed, getSpeedColor } = await import('maps_maplibre/utils/speed_colors')

      const routesGeoJSON = await this.generateRoutesWithSpeedColors(
        points,
        { distanceThresholdMeters, timeThresholdMinutes },
        calculateSpeed,
        getSpeedColor
      )

      this.layerManager.updateLayer('routes', routesGeoJSON)

    } catch (error) {
      console.error('Failed to reload routes:', error)
      Toast.error('Failed to reload routes')
    } finally {
      this.controller.hideLoading()
    }
  }

  /**
   * Generate routes with speed coloring
   */
  async generateRoutesWithSpeedColors(points, options, calculateSpeed, getSpeedColor) {
    const { RoutesLayer } = await import('maps_maplibre/layers/routes_layer')
    const useSpeedColors = this.settings.speedColoredRoutesEnabled || false
    const speedColorScale = this.settings.speedColorScale || '0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300'

    const routesGeoJSON = RoutesLayer.pointsToRoutes(points, options)

    if (!useSpeedColors) {
      return routesGeoJSON
    }

    routesGeoJSON.features = routesGeoJSON.features.map((feature, index) => {
      const segment = points.slice(
        points.findIndex(p => p.timestamp === feature.properties.startTime),
        points.findIndex(p => p.timestamp === feature.properties.endTime) + 1
      )

      if (segment.length >= 2) {
        const speed = calculateSpeed(segment[0], segment[segment.length - 1])
        const color = getSpeedColor(speed, useSpeedColors, speedColorScale)
        feature.properties.speed = speed
        feature.properties.color = color
      }

      return feature
    })

    return routesGeoJSON
  }

  /**
   * Toggle heatmap visibility
   */
  toggleHeatmap(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('heatmapEnabled', enabled)

    const heatmapLayer = this.layerManager.getLayer('heatmap')
    if (heatmapLayer) {
      if (enabled) {
        heatmapLayer.show()
      } else {
        heatmapLayer.hide()
      }
    }
  }

  /**
   * Toggle fog of war layer
   */
  toggleFog(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('fogEnabled', enabled)

    const fogLayer = this.layerManager.getLayer('fog')
    if (fogLayer) {
      fogLayer.toggle(enabled)
    } else {
      console.warn('Fog layer not yet initialized')
    }
  }

  /**
   * Toggle scratch map layer
   */
  async toggleScratch(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('scratchEnabled', enabled)

    try {
      const scratchLayer = this.layerManager.getLayer('scratch')
      if (!scratchLayer && enabled) {
        const ScratchLayer = await lazyLoader.loadLayer('scratch')
        const newScratchLayer = new ScratchLayer(this.map, {
          visible: true,
          apiClient: this.controller.api
        })
        const pointsLayer = this.layerManager.getLayer('points')
        const pointsData = pointsLayer?.data || { type: 'FeatureCollection', features: [] }
        await newScratchLayer.add(pointsData)
        this.layerManager.layers.scratchLayer = newScratchLayer
      } else if (scratchLayer) {
        if (enabled) {
          scratchLayer.show()
        } else {
          scratchLayer.hide()
        }
      }
    } catch (error) {
      console.error('Failed to toggle scratch layer:', error)
      Toast.error('Failed to load scratch layer')
    }
  }

  /**
   * Toggle photos layer
   */
  togglePhotos(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('photosEnabled', enabled)

    const photosLayer = this.layerManager.getLayer('photos')
    if (photosLayer) {
      if (enabled) {
        photosLayer.show()
      } else {
        photosLayer.hide()
      }
    }
  }

  /**
   * Toggle areas layer
   */
  toggleAreas(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('areasEnabled', enabled)

    const areasLayer = this.layerManager.getLayer('areas')
    if (areasLayer) {
      if (enabled) {
        areasLayer.show()
      } else {
        areasLayer.hide()
      }
    }
  }

  /**
   * Toggle tracks layer
   */
  toggleTracks(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('tracksEnabled', enabled)

    const tracksLayer = this.layerManager.getLayer('tracks')
    if (tracksLayer) {
      if (enabled) {
        tracksLayer.show()
      } else {
        tracksLayer.hide()
      }
    }
  }

  /**
   * Toggle points layer visibility
   */
  togglePoints(event) {
    const element = event.currentTarget
    const visible = element.checked

    const pointsLayer = this.layerManager.getLayer('points')
    if (pointsLayer) {
      pointsLayer.toggle(visible)
    }

    SettingsManager.updateSetting('pointsVisible', visible)
  }
}
