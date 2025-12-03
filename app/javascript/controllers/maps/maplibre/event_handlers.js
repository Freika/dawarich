import { formatTimestamp } from 'maps_maplibre/utils/geojson_transformers'

/**
 * Handles map interaction events (clicks, info display)
 */
export class EventHandlers {
  constructor(map, controller) {
    this.map = map
    this.controller = controller
  }

  /**
   * Handle point click
   */
  handlePointClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        <div><span class="font-semibold">Time:</span> ${formatTimestamp(properties.timestamp)}</div>
        ${properties.battery ? `<div><span class="font-semibold">Battery:</span> ${properties.battery}%</div>` : ''}
        ${properties.altitude ? `<div><span class="font-semibold">Altitude:</span> ${Math.round(properties.altitude)}m</div>` : ''}
        ${properties.velocity ? `<div><span class="font-semibold">Speed:</span> ${Math.round(properties.velocity)} km/h</div>` : ''}
      </div>
    `

    this.controller.showInfo('Location Point', content)
  }

  /**
   * Handle visit click
   */
  handleVisitClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const startTime = formatTimestamp(properties.started_at)
    const endTime = formatTimestamp(properties.ended_at)
    const durationHours = Math.round(properties.duration / 3600)
    const durationDisplay = durationHours >= 1 ? `${durationHours}h` : `${Math.round(properties.duration / 60)}m`

    const content = `
      <div class="space-y-2">
        <div class="badge badge-sm ${properties.status === 'confirmed' ? 'badge-success' : 'badge-warning'}">${properties.status}</div>
        <div><span class="font-semibold">Arrived:</span> ${startTime}</div>
        <div><span class="font-semibold">Left:</span> ${endTime}</div>
        <div><span class="font-semibold">Duration:</span> ${durationDisplay}</div>
      </div>
    `

    const actions = [{ url: `/visits/${properties.id}`, label: 'View Details →' }]

    this.controller.showInfo(properties.name || properties.place_name || 'Visit', content, actions)
  }

  /**
   * Handle photo click
   */
  handlePhotoClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.photo_url ? `<img src="${properties.photo_url}" alt="Photo" class="w-full rounded-lg mb-2" />` : ''}
        ${properties.taken_at ? `<div><span class="font-semibold">Taken:</span> ${formatTimestamp(properties.taken_at)}</div>` : ''}
      </div>
    `

    this.controller.showInfo('Photo', content)
  }

  /**
   * Handle place click
   */
  handlePlaceClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.tag ? `<div class="badge badge-sm badge-primary">${properties.tag}</div>` : ''}
        ${properties.description ? `<div>${properties.description}</div>` : ''}
      </div>
    `

    const actions = properties.id ? [{ url: `/places/${properties.id}`, label: 'View Details →' }] : []

    this.controller.showInfo(properties.name || 'Place', content, actions)
  }

  /**
   * Handle area click
   */
  handleAreaClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.radius ? `<div><span class="font-semibold">Radius:</span> ${Math.round(properties.radius)}m</div>` : ''}
        ${properties.latitude && properties.longitude ? `<div><span class="font-semibold">Center:</span> ${properties.latitude.toFixed(6)}, ${properties.longitude.toFixed(6)}</div>` : ''}
      </div>
    `

    const actions = properties.id ? [{ url: `/areas/${properties.id}`, label: 'View Details →' }] : []

    this.controller.showInfo(properties.name || 'Area', content, actions)
  }
}
