export const MapHook = {
  async mounted() {
    this.mapDestroyed = false
    this.mapRevoked = false
    this.mapReady = false
    this.mapConfig = null
    this.mapRealtime = null
    this.mapInvalidations = []
    this.mapHandlers = [
      this.handleEvent("map:config", (payload) => {
        this.mapConfig = payload
        return this.mapOwner?.update(payload)
      }),
      this.handleEvent("map:invalidate", (receipt = {}) => {
        if (this.mapDestroyed || this.mapRevoked) return
        if (this.mapReady) return this.mapRealtime.invalidate(receipt)
        this.mapInvalidations.push({
          kind: receipt.kind,
          revision: receipt.revision,
        })
        if (this.mapInvalidations.length > 32) this.mapInvalidations.shift()
      }),
      this.handleEvent("map:clear", () => {
        this.mapRevoked = true
        this.mapRealtime?.destroy()
        this.mapOwner?.destroy()
        this.mapInvalidations = []
      }),
    ]
    try {
      const [runtime, { createRealtime }] = await Promise.all([
        (this.loader ?? (() => import("../map/runtime/host.js")))(),
        import("../map/data/realtime.js"),
      ])
      if (this.mapDestroyed || this.mapRevoked) return
      this.mapRealtime = createRealtime({
        run: () => this.mapOwner?.reconnect(),
        timers: this.mapTimers ?? globalThis,
      })
      this.mapOwner = runtime.mountHost({
        element: this.el,
        pushEvent: this.pushEvent.bind(this),
      })
      if (this.mapConfig) await this.mapOwner.update(this.mapConfig)
      await this.mapOwner.mount()
      if (this.mapDestroyed || this.mapRevoked) return
      this.mapReady = true
      for (const receipt of this.mapInvalidations)
        this.mapRealtime.invalidate(receipt)
      this.mapInvalidations = []
    } catch {
      this.mapRealtime?.destroy()
      if (!this.mapDestroyed) this.el.dataset.mapState = "failed"
    }
  },
  reconnected() {
    if (this.mapReady) return this.mapRealtime?.reconnect()
    if (this.mapInvalidations?.length < 32) this.mapInvalidations.push({})
  },
  destroyed() {
    this.mapDestroyed = true
    this.mapRealtime?.destroy()
    this.mapInvalidations = []
    for (const ref of this.mapHandlers ?? []) this.removeHandleEvent(ref)
    this.mapHandlers = []
    this.mapOwner?.destroy()
    this.mapOwner = null
  },
}
