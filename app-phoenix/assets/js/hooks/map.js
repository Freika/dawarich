export const MapHook = {
  async mounted() {
    this.mapDestroyed = false
    this.mapRevoked = false
    this.mapConfig = null
    this.mapHandlers = [
      this.handleEvent("map:config", (payload) => {
        this.mapConfig = payload
        return this.mapOwner?.update(payload)
      }),
      this.handleEvent("map:invalidate", () => this.mapOwner?.reconnect()),
      this.handleEvent("map:clear", () => {
        this.mapRevoked = true
        this.mapOwner?.destroy()
      }),
    ]
    try {
      const runtime = await (
        this.loader ?? (() => import("../map/runtime/host.js"))
      )()
      if (this.mapDestroyed || this.mapRevoked) return
      this.mapOwner = runtime.mountHost({
        element: this.el,
        pushEvent: this.pushEvent.bind(this),
      })
      if (this.mapConfig) await this.mapOwner.update(this.mapConfig)
      await this.mapOwner.mount()
    } catch {
      if (!this.mapDestroyed) this.el.dataset.mapState = "failed"
    }
  },
  reconnected() {
    return this.mapOwner?.reconnect()
  },
  destroyed() {
    this.mapDestroyed = true
    for (const ref of this.mapHandlers ?? []) this.removeHandleEvent(ref)
    this.mapHandlers = []
    this.mapOwner?.destroy()
    this.mapOwner = null
  },
}
