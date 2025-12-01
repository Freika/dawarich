import maplibregl from 'maplibre-gl'
import { PopupFactory } from 'maps_maplibre/components/popup_factory'
import { VisitPopupFactory } from 'maps_maplibre/components/visit_popup'
import { PhotoPopupFactory } from 'maps_maplibre/components/photo_popup'

/**
 * Handles map interaction events (clicks, popups)
 */
export class EventHandlers {
  constructor(map) {
    this.map = map
  }

  /**
   * Handle point click
   */
  handlePointClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(PopupFactory.createPointPopup(properties))
      .addTo(this.map)
  }

  /**
   * Handle visit click
   */
  handleVisitClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(VisitPopupFactory.createVisitPopup(properties))
      .addTo(this.map)
  }

  /**
   * Handle photo click
   */
  handlePhotoClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(PhotoPopupFactory.createPhotoPopup(properties))
      .addTo(this.map)
  }

  /**
   * Handle place click
   */
  handlePlaceClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(PopupFactory.createPlacePopup(properties))
      .addTo(this.map)
  }
}
