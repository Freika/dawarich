import { MapState } from "./map_state.js"
export const MapHook = {
  ...MapState,
  async mounted() {
    this.mapDestroyed = false
    this.mapRevoked = false
    this.mapReady = false
    this.mapConfig = null
    this.mapTrackSelection = null
    this.mapVisitSelection = null
    this.mapPlaceFocus = null
    this.mapDayFit = null
    this.mapRealtime = null
    this.mapInvalidations = []
    this.mapHandlers = [
      this.handleEvent("place:focus", ({ latitude, longitude }) => {
        if (
          this.mapDestroyed ||
          this.mapRevoked ||
          !Number.isFinite(latitude) ||
          !Number.isFinite(longitude) ||
          Math.abs(latitude) > 90 ||
          Math.abs(longitude) > 180
        )
          return
        this.mapPlaceFocus = { center: [longitude, latitude], zoom: 16 }
        if (this.mapReady) this.mapOwner?.map?.jumpTo(this.mapPlaceFocus)
      }),
      this.handleEvent("timeline:fit", ({ bounds } = {}) => {
        const { sw_lng, sw_lat, ne_lng, ne_lat } = bounds || {}
        if (
          this.mapDestroyed ||
          this.mapRevoked ||
          ![sw_lng, sw_lat, ne_lng, ne_lat].every(Number.isFinite)
        )
          return
        this.mapDayFit = [
          [sw_lng, sw_lat],
          [ne_lng, ne_lat],
        ]
        if (this.mapReady) this.fitDay()
      }),
      this.handleEvent("visit:selection", (payload) => {
        if (this.mapDestroyed || this.mapRevoked) return
        this.mapVisitSelection = { id: payload.id }
        if (this.mapReady)
          return this.mapOwner?.visits?.select(this.mapVisitSelection)
      }),
      this.handleEvent("track:selection", (payload) => {
        if (this.mapDestroyed || this.mapRevoked) return
        this.mapTrackSelection = {
          id: payload.id,
          points: payload.points === true,
        }
        if (this.mapReady)
          return this.mapOwner?.timeline?.select(this.mapTrackSelection)
      }),
      this.handleEvent("map:layer", (payload) =>
        this.mapOwner?.layer?.(payload),
      ),
      this.handleEvent("map:settings", (payload) =>
        this.mapOwner?.settings?.(payload),
      ),
      this.handleEvent("enrichment:matches", (payload) =>
        this.mapOwner?.enrichment?.matches(payload),
      ),
      this.handleEvent("map:config", (payload) => {
        this.mapConfig = payload
        if (typeof payload.panel === "string") {
          this.el.classList.toggle("panel-open", payload.panel !== "")
          this.el.classList.toggle(
            "panel-timeline-expanded",
            payload.panel === "timeline",
          )
        }
        return this.mapOwner?.update({ ...this.mapOwner.config, ...payload })
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
        (this.loader ?? (() => import("../runtime/host.js"))).call(this),
        import("../data/realtime.js"),
      ])
      if (this.mapDestroyed || this.mapRevoked) return
      this.mapRealtime = createRealtime({
        run: (receipt) => this.mapOwner?.reconnect(receipt),
        timers: this.mapTimers ?? globalThis,
      })
      this.mapOwner = runtime.mountHost({
        element: this.el,
        pushEvent: this.pushEvent.bind(this),
      })
      if (this.mapConfig)
        await this.mapOwner.update({
          ...this.mapOwner.config,
          ...this.mapConfig,
        })
      await this.mapOwner.mount()
      if (this.mapDestroyed || this.mapRevoked) return
      if (this.mapTrackSelection)
        await this.mapOwner.timeline?.select(this.mapTrackSelection)
      if (this.mapDestroyed || this.mapRevoked) return
      if (this.mapVisitSelection)
        await this.mapOwner.visits?.select(this.mapVisitSelection)
      if (this.mapDestroyed || this.mapRevoked) return
      this.mapReady = true
      const entry = this.el.ownerDocument?.location?.href
      if (entry)
        this.mapOwner.openStudio?.(new URL(entry).searchParams.get("studio"))
      if (this.mapPlaceFocus) this.mapOwner?.map?.jumpTo(this.mapPlaceFocus)
      if (this.mapDayFit) this.fitDay()
      for (const receipt of this.mapInvalidations)
        this.mapRealtime.invalidate(receipt)
      this.mapInvalidations = []
    } catch {
      this.mapRealtime?.destroy()
      if (!this.mapDestroyed) this.el.dataset.mapState = "failed"
    }
  },
  fitDay() {
    const bounds = this.mapDayFit
    this.mapDayFit = null
    this.mapOwner?.map?.fitBounds?.(bounds, { padding: 60, duration: 500 })
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
