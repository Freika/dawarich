import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { NotesLayer, notesToGeoJSON } from "maps_maplibre/layers/notes_layer"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"

const DAY_MS = 24 * 60 * 60 * 1000
// Layers whose features carry the moment a click on them refers to.
const MOMENT_LAYERS = { visits: "started_at", "points-mvt": "timestamp" }

/**
 * Map Notes on the main map: the layer, its toggle, placing a note by
 * clicking the map and opening one by clicking its dot. The form lives in a
 * server-rendered dialog (map_note_controller); this class talks to it
 * through document events.
 */
export class NotesManager {
  constructor(controller) {
    this.controller = controller
    this.reload = this.reload.bind(this)
    this.onNoteClick = (event) => {
      const id = event.features?.[0]?.properties?.id
      if (id) this.emit("note:edit", { id })
    }
    this.onStyleData = () => {
      if (this.layer && !this.map.getSource(this.layer.sourceId)) this.render()
    }
    this.onEscape = (event) => {
      if (event.key === "Escape") this.disarm()
    }
    // A note the user just wrote must be visible, so saving turns the layer on.
    this.onSaved = () => {
      if (!this.enabled) this.setEnabled(true)
      if (this.controller.hasNotesToggleTarget) {
        this.controller.notesToggleTarget.checked = true
      }
      this.onChanged()
    }
    // The open day lists its notes, so it follows every change too.
    this.onChanged = () => {
      this.reload()
      this.controller.refreshTimelineFeedIfActive?.()
    }
    // A note picked in the timeline: bring it into view, with its dot marked.
    // The dot has to be there to be seen, so this turns the layer on.
    this.onSelected = async (event) => {
      const { id, lat, lng } = event.detail || {}
      if (lat === null || lng === null || !this.map) return
      if (!this.enabled) {
        this.setEnabled(true)
        if (this.controller.hasNotesToggleTarget) {
          this.controller.notesToggleTarget.checked = true
        }
        await this.reload()
      }
      this.layer?.select(id)
      this.map.flyTo({
        center: [lng, lat],
        zoom: Math.max(this.map.getZoom(), 15),
        duration: 600,
      })
    }
    document.addEventListener("note:saved", this.onSaved)
    document.addEventListener("note:deleted", this.onChanged)
    document.addEventListener("timeline-feed:note-selected", this.onSelected)
  }

  setEnabled(enabled) {
    SettingsManager.updateSetting("notesEnabled", enabled)
    this.controller.settings.notesEnabled = enabled
  }

  get map() {
    return this.controller.map
  }

  get enabled() {
    return this.controller.settings.notesEnabled === true
  }

  async toggle(event) {
    this.setEnabled(event.target.checked)
    await this.reload()
  }

  // Called after every map data load: the layer follows the selected period.
  async reload() {
    if (!this.enabled) {
      this.layer?.hide()
      return
    }

    try {
      const notes = await this.controller.api.fetchNotes({
        start_at: this.controller.startDateValue,
        end_at: this.controller.endDateValue,
      })
      this.render(notesToGeoJSON(notes))
    } catch (error) {
      console.error("Failed to load notes:", error)
      Toast.error(translate("messages.failed_to_load_notes"))
    }
  }

  render(data) {
    if (!this.layer) {
      this.layer = new NotesLayer(this.map)
      this.map.on("click", "notes", this.onNoteClick)
      this.map.on("styledata", this.onStyleData)
    }
    this.layer.render(data)
    this.layer.show()
  }

  startCreate() {
    this.disarm()
    this.map.getCanvas().style.cursor = "crosshair"
    Toast.info(translate("messages.click_on_the_map_to_place_a_note_esc_to"))

    this.onPlaceClick = (event) => {
      this.disarm()
      this.emit("note:new", {
        latitude: event.lngLat.lat,
        longitude: event.lngLat.lng,
        notedAt: this.momentAt(event.point),
      })
    }
    this.map.once("click", this.onPlaceClick)
    document.addEventListener("keydown", this.onEscape)
  }

  disarm() {
    if (!this.onPlaceClick) return

    this.map.off("click", this.onPlaceClick)
    this.onPlaceClick = null
    document.removeEventListener("keydown", this.onEscape)
    this.map.getCanvas().style.cursor = ""
  }

  /**
   * The moment a new note describes: the time of the visit or track point
   * under the click; otherwise noon of the day selected in the Timeline, or
   * the middle of a single viewed day in the past.
   * Returns undefined to let the server use the current time.
   */
  momentAt(point) {
    const layers = Object.keys(MOMENT_LAYERS).filter((id) =>
      this.map.getLayer(id),
    )
    const feature = this.map.queryRenderedFeatures(point, { layers })[0]
    const value = feature?.properties?.[MOMENT_LAYERS[feature.layer.id]]
    if (value) {
      // Point tiles carry epoch seconds, visits an ISO string.
      const date = new Date(typeof value === "number" ? value * 1000 : value)
      if (!Number.isNaN(date.getTime())) return date.toISOString()
    }

    const selectedDay = this.controller._highlightedDay
    if (selectedDay) {
      // The day is one of the account's calendar. So is "today", and the
      // noon sent without a zone is read by the server on the same clock.
      const today = new Date().toLocaleDateString("en-CA", {
        timeZone: this.controller.timezoneValue || undefined,
      })
      return selectedDay === today ? undefined : `${selectedDay}T12:00`
    }

    const start = new Date(this.controller.startDateValue).getTime()
    const end = new Date(this.controller.endDateValue).getTime()
    const now = Date.now()
    if (end - start > DAY_MS || (now >= start && now <= end)) return undefined

    return new Date((start + end) / 2).toISOString()
  }

  emit(name, detail) {
    document.dispatchEvent(new CustomEvent(name, { detail }))
  }

  destroy() {
    this.disarm()
    document.removeEventListener("note:saved", this.onSaved)
    document.removeEventListener("note:deleted", this.onChanged)
    document.removeEventListener("timeline-feed:note-selected", this.onSelected)
    this.map?.off("click", "notes", this.onNoteClick)
    this.map?.off("styledata", this.onStyleData)
  }
}
