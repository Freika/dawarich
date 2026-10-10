import { MapHook } from "./map.js"
export const TripHook = {
  ...MapHook,
  loader: () =>
    import("../map/trip/runtime.js").then((module) => ({
      mountHost: module.mountTrip,
    })),
  async mounted() {
    this.tripDay = undefined
    this.tripDayPending = false
    this.tripDayHandler = this.handleEvent("trip:select_day", ({ day }) => {
      if (this.mapDestroyed || this.mapRevoked) return
      if (
        day !== null &&
        (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day))
      )
        return
      this.tripDay = day
      this.tripDayPending = !this.mapReady
      if (this.mapReady) this.mapOwner?.layers?.selectDay?.(day)
    })
    await MapHook.mounted.call(this)
    if (
      this.mapReady &&
      !this.mapDestroyed &&
      !this.mapRevoked &&
      this.tripDayPending
    ) {
      this.tripDayPending = false
      this.mapOwner?.layers?.selectDay?.(this.tripDay)
    }
  },
  destroyed() {
    if (this.tripDayHandler !== null && this.tripDayHandler !== undefined)
      this.removeHandleEvent(this.tripDayHandler)
    this.tripDayHandler = null
    this.tripDay = undefined
    this.tripDayPending = false
    MapHook.destroyed.call(this)
  },
}
