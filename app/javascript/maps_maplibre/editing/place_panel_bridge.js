import { removePlaceFeature } from "maps_maplibre/components/place_actions"
import { consumePlaceParams } from "maps_maplibre/editing/place_editor_state"
import { PlaceGeometryEditor } from "maps_maplibre/editing/place_geometry_editor"

export class PlacePanelBridge {
  constructor(controller) {
    this.controller = controller
    this.editor = new PlaceGeometryEditor(controller.map)
    const listen = (type, handler) =>
      controller.cleanup.addEventListener(document, type, handler)
    listen("place:map-edit", (event) =>
      this.editor.start(event.detail.place, event.detail.maximum),
    )
    for (const type of [
      "place:map-cancel",
      "place:panel-closed",
      "place:open",
      "place:updated",
    ]) {
      listen(type, () => this.editor.stop())
    }
    listen("place:updated", () =>
      document
        .querySelector(".place-panel")
        ?.classList.remove("place-panel--editing"),
    )
    listen("place:removed", (event) =>
      removePlaceFeature(controller, event.detail.id),
    )
    listen("place:deleted", (event) => this.deleted(event.detail.id))
    const params = consumePlaceParams(window.location.href)
    if (params) {
      history.replaceState(history.state, "", params.url)
      this.open(params.id, params.edit)
    }
  }

  open(id, edit = false) {
    this.controller.closeInfo()
    document.dispatchEvent(
      new CustomEvent("place:open", { detail: { id, edit } }),
    )
  }

  async deleted(id) {
    removePlaceFeature(this.controller, id)
    const panel = document.querySelector('[data-controller="place-panel"]')
    this.controller.application
      .getControllerForElementAndIdentifier(panel, "place-panel")
      ?.close()
    await this.controller.placesManager._refreshPrivacyZones()
  }

  destroy() {
    this.editor.stop()
  }
}
