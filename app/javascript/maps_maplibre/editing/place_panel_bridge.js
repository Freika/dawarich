import { removePlaceFeature } from "maps_maplibre/components/place_actions"
import { PlaceCamera } from "maps_maplibre/editing/place_camera"
import {
  consumePlaceParams,
  shouldCenterPlace,
} from "maps_maplibre/editing/place_editor_state"
import { PlaceGeometryEditor } from "maps_maplibre/editing/place_geometry_editor"
import { SelectedPlaceLayer } from "maps_maplibre/editing/selected_place_layer"

export class PlacePanelBridge {
  constructor(controller) {
    this.controller = controller
    this.editor = new PlaceGeometryEditor(controller.map)
    this.camera = new PlaceCamera(controller.map)
    this.selection = new SelectedPlaceLayer(controller.map, (id) =>
      this.open(id),
    )
    const listen = (type, handler) =>
      controller.cleanup.addEventListener(document, type, handler)
    listen("place:map-edit", (event) => {
      this.selection.clear()
      this.editor.start(event.detail.place, event.detail.maximum)
    })
    listen("place:map-cancel", () => {
      this.editor.stop()
      if (this.place && !this.place.privacy_hidden) {
        this.selection.show(this.place)
        this.camera.fit(this.place)
      }
    })
    listen("place:panel-closed", () => this.clear())
    listen("place:panel-loaded", (event) => this.loaded(event.detail.place))
    listen("place:updated", () => this.editor.stop())
    listen("place:removed", (event) =>
      removePlaceFeature(controller, event.detail.id),
    )
    listen("place:deleted", (event) => this.deleted(event.detail.id))
    const params = consumePlaceParams(window.location.href)
    if (params) {
      history.replaceState(history.state, "", params.url)
      this.open(params.id, params.edit, "link")
    }
  }

  open(id, edit = false, origin = "map") {
    if (!edit && Number(id) === this.id) return
    this.controller.closeInfo()
    this.clear()
    this.id = Number(id)
    this.centerPending = shouldCenterPlace({ origin, edit })
    document.dispatchEvent(
      new CustomEvent("place:open", { detail: { id, edit } }),
    )
  }

  get isOpen() {
    return this.id != null
  }

  loaded(place) {
    if (place.id !== this.id) return
    this.place = place
    this.editor.stop()
    if (place.privacy_hidden) {
      this.selection.clear()
      this.camera.cancel()
    } else {
      this.selection.show(place)
      if (this.centerPending) this.camera.fit(place)
    }
    this.centerPending = false
  }

  clear() {
    this.id = null
    this.place = null
    this.centerPending = false
    this.camera.cancel()
    this.editor.stop()
    this.selection.clear()
  }

  async deleted(id) {
    removePlaceFeature(this.controller, id)
    if (Number(id) === this.id) {
      const panel = document.querySelector('[data-controller="place-panel"]')
      this.controller.application
        .getControllerForElementAndIdentifier(panel, "place-panel")
        ?.close()
    }
    await this.controller.placesManager._refreshPrivacyZones()
  }

  destroy() {
    this.clear()
    this.selection.destroy()
  }
}
