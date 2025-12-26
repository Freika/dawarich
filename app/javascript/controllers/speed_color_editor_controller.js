import { Controller } from '@hotwired/stimulus'

/**
 * Speed Color Editor Controller
 * Manages the gradient editor modal for speed-colored routes
 */
export default class extends Controller {
  static targets = ['modal', 'stopsList', 'preview']
  static values = {
    colorStops: String
  }

  connect() {
    this.loadColorStops()
  }

  loadColorStops() {
    const stopsString = this.colorStopsValue || '0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300'
    this.stops = this.parseColorStops(stopsString)
    this.renderStops()
    this.updatePreview()
  }

  parseColorStops(stopsString) {
    return stopsString.split('|').map(segment => {
      const [speed, color] = segment.split(':')
      return { speed: Number(speed), color }
    })
  }

  serializeColorStops() {
    return this.stops.map(stop => `${stop.speed}:${stop.color}`).join('|')
  }

  renderStops() {
    if (!this.hasStopsListTarget) return

    this.stopsListTarget.innerHTML = this.stops.map((stop, index) => `
      <div class="flex items-center gap-3 p-3 bg-base-200 rounded-lg" data-index="${index}">
        <div class="flex-1">
          <label class="label">
            <span class="label-text text-sm">Speed (km/h)</span>
          </label>
          <input type="number"
                 class="input input-bordered input-sm w-full"
                 value="${stop.speed}"
                 min="0"
                 max="200"
                 data-action="input->speed-color-editor#updateSpeed"
                 data-index="${index}" />
        </div>

        <div class="flex-1">
          <label class="label">
            <span class="label-text text-sm">Color</span>
          </label>
          <div class="flex gap-2 items-center">
            <input type="color"
                   class="w-12 h-10 rounded cursor-pointer border-2 border-base-300"
                   value="${stop.color}"
                   data-action="input->speed-color-editor#updateColor"
                   data-index="${index}" />
            <input type="text"
                   class="input input-bordered input-sm w-24 font-mono text-xs"
                   value="${stop.color}"
                   pattern="^#[0-9A-Fa-f]{6}$"
                   data-action="input->speed-color-editor#updateColorText"
                   data-index="${index}" />
          </div>
        </div>

        <button type="button"
                class="btn btn-sm btn-ghost btn-circle text-error mt-6"
                data-action="click->speed-color-editor#removeStop"
                data-index="${index}"
                ${this.stops.length <= 2 ? 'disabled' : ''}>
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `).join('')
  }

  updateSpeed(event) {
    const index = parseInt(event.target.dataset.index)
    this.stops[index].speed = Number(event.target.value)
    this.updatePreview()
  }

  updateColor(event) {
    const index = parseInt(event.target.dataset.index)
    const color = event.target.value
    this.stops[index].color = color

    // Update text input
    const textInput = event.target.parentElement.querySelector('input[type="text"]')
    if (textInput) {
      textInput.value = color
    }

    this.updatePreview()
  }

  updateColorText(event) {
    const index = parseInt(event.target.dataset.index)
    const color = event.target.value

    if (/^#[0-9A-Fa-f]{6}$/.test(color)) {
      this.stops[index].color = color

      // Update color picker
      const colorInput = event.target.parentElement.querySelector('input[type="color"]')
      if (colorInput) {
        colorInput.value = color
      }

      this.updatePreview()
    }
  }

  addStop() {
    // Find a good speed value between existing stops
    const lastStop = this.stops[this.stops.length - 1]
    const newSpeed = lastStop.speed + 10

    this.stops.push({
      speed: newSpeed,
      color: '#ff0000'
    })

    // Sort by speed
    this.stops.sort((a, b) => a.speed - b.speed)

    this.renderStops()
    this.updatePreview()
  }

  removeStop(event) {
    const index = parseInt(event.target.dataset.index)

    if (this.stops.length > 2) {
      this.stops.splice(index, 1)
      this.renderStops()
      this.updatePreview()
    }
  }

  updatePreview() {
    if (!this.hasPreviewTarget) return

    const gradient = this.stops.map((stop, index) => {
      const percentage = (index / (this.stops.length - 1)) * 100
      return `${stop.color} ${percentage}%`
    }).join(', ')

    this.previewTarget.style.background = `linear-gradient(to right, ${gradient})`
  }

  save() {
    const serialized = this.serializeColorStops()

    // Dispatch event with the new color stops
    this.dispatch('save', {
      detail: { colorStops: serialized }
    })

    this.close()
  }

  close() {
    if (this.hasModalTarget) {
      const checkbox = this.modalTarget.querySelector('.modal-toggle')
      if (checkbox) {
        checkbox.checked = false
      }
    }
  }

  resetToDefault() {
    this.colorStopsValue = '0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300'
    this.loadColorStops()
  }
}
