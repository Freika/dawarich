import { SettingsManager } from 'maps_maplibre/utils/settings_manager'
import { Toast } from 'maps_maplibre/components/toast'

/**
 * Manages visits-related operations for Maps V2
 * Including visit creation, filtering, and layer management
 */
export class VisitsManager {
  constructor(controller) {
    this.controller = controller
    this.layerManager = controller.layerManager
    this.filterManager = controller.filterManager
    this.api = controller.api
    this.dataLoader = controller.dataLoader
  }

  /**
   * Toggle visits layer
   */
  toggleVisits(event) {
    const enabled = event.target.checked
    SettingsManager.updateSetting('visitsEnabled', enabled)

    const visitsLayer = this.layerManager.getLayer('visits')
    if (visitsLayer) {
      if (enabled) {
        visitsLayer.show()
        if (this.controller.hasVisitsSearchTarget) {
          this.controller.visitsSearchTarget.style.display = 'block'
        }
      } else {
        visitsLayer.hide()
        if (this.controller.hasVisitsSearchTarget) {
          this.controller.visitsSearchTarget.style.display = 'none'
        }
      }
    }
  }

  /**
   * Search visits
   */
  searchVisits(event) {
    const searchTerm = event.target.value.toLowerCase()
    const visitsLayer = this.layerManager.getLayer('visits')
    this.filterManager.filterAndUpdateVisits(
      searchTerm,
      this.filterManager.getCurrentVisitFilter(),
      visitsLayer
    )
  }

  /**
   * Filter visits by status
   */
  filterVisits(event) {
    const filter = event.target.value
    this.filterManager.setCurrentVisitFilter(filter)
    const searchTerm = document.getElementById('visits-search')?.value.toLowerCase() || ''
    const visitsLayer = this.layerManager.getLayer('visits')
    this.filterManager.filterAndUpdateVisits(searchTerm, filter, visitsLayer)
  }

  /**
   * Start create visit mode
   */
  startCreateVisit() {
    console.log('[Maps V2] Starting create visit mode')

    if (this.controller.hasSettingsPanelTarget && this.controller.settingsPanelTarget.classList.contains('open')) {
      this.controller.toggleSettings()
    }

    this.controller.map.getCanvas().style.cursor = 'crosshair'
    Toast.info('Click on the map to place a visit')

    this.handleCreateVisitClick = (e) => {
      const { lng, lat } = e.lngLat
      this.openVisitCreationModal(lat, lng)
      this.controller.map.getCanvas().style.cursor = ''
    }

    this.controller.map.once('click', this.handleCreateVisitClick)
  }

  /**
   * Open visit creation modal
   */
  openVisitCreationModal(lat, lng) {
    console.log('[Maps V2] Opening visit creation modal', { lat, lng })

    const modalElement = document.querySelector('[data-controller="visit-creation-v2"]')

    if (!modalElement) {
      console.error('[Maps V2] Visit creation modal not found')
      Toast.error('Visit creation modal not available')
      return
    }

    const controller = this.controller.application.getControllerForElementAndIdentifier(
      modalElement,
      'visit-creation-v2'
    )

    if (controller) {
      controller.open(lat, lng, this.controller)
    } else {
      console.error('[Maps V2] Visit creation controller not found')
      Toast.error('Visit creation controller not available')
    }
  }

  /**
   * Handle visit creation event - reload visits and update layer
   */
  async handleVisitCreated(event) {
    console.log('[Maps V2] Visit created, reloading visits...', event.detail)

    try {
      const visits = await this.api.fetchVisits({
        start_at: this.controller.startDateValue,
        end_at: this.controller.endDateValue
      })

      console.log('[Maps V2] Fetched visits:', visits.length)

      this.filterManager.setAllVisits(visits)
      const visitsGeoJSON = this.dataLoader.visitsToGeoJSON(visits)

      console.log('[Maps V2] Converted to GeoJSON:', visitsGeoJSON.features.length, 'features')

      const visitsLayer = this.layerManager.getLayer('visits')
      if (visitsLayer) {
        visitsLayer.update(visitsGeoJSON)
        console.log('[Maps V2] Visits layer updated successfully')
      } else {
        console.warn('[Maps V2] Visits layer not found, cannot update')
      }
    } catch (error) {
      console.error('[Maps V2] Failed to reload visits:', error)
    }
  }
}
