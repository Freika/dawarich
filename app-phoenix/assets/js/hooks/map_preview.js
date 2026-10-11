import { rememberMapState, restoreMapState } from "./map_state.js"
export const MapPreview = {
  async mounted() {
    this.previewDestroyed = false
    try {
      const { mountPreview } = await (
        this.loader ?? (() => import("../map/preview/runtime.js"))
      )()
      if (this.previewDestroyed) return
      this.previewOwner = mountPreview({ element: this.el })
      this.previewOwner.mount()
    } catch {
      if (!this.previewDestroyed) this.el.dataset.mapState = "failed"
    }
  },
  beforeUpdate() {
    rememberMapState(this)
  },
  updated() {
    restoreMapState(this)
    return this.previewOwner?.update(
      JSON.parse(this.el.dataset.mapConfig ?? "{}"),
    )
  },
  reconnected() {
    return this.previewOwner?.reconnect()
  },
  destroyed() {
    this.previewDestroyed = true
    this.previewOwner?.destroy()
    this.previewOwner = null
  },
}
