import { MapHook } from "./map.js"
export const PublicMap = {
  ...MapHook,
  loader: () =>
    import("../map/public/runtime.js").then((module) => ({
      mountHost: module.mountPublic,
    })),
  async mounted() {
    this.publicDay = undefined
    this.publicDayPending = false
    this.publicDayHandler = this.handleEvent("public:day", ({ day }) => {
      if (this.mapDestroyed || this.mapRevoked) return
      if (
        day !== null &&
        (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day))
      )
        return
      this.publicDay = day
      this.publicDayPending = !this.mapReady
      if (this.mapReady) this.mapOwner?.selectDay?.(day)
    })
    await MapHook.mounted.call(this)
    if (
      this.mapReady &&
      !this.mapDestroyed &&
      !this.mapRevoked &&
      this.publicDayPending
    ) {
      this.publicDayPending = false
      this.mapOwner?.selectDay?.(this.publicDay)
    }
  },
  destroyed() {
    if (this.publicDayHandler !== null && this.publicDayHandler !== undefined)
      this.removeHandleEvent(this.publicDayHandler)
    this.publicDayHandler = null
    this.publicDay = undefined
    this.publicDayPending = false
    MapHook.destroyed.call(this)
  },
}
