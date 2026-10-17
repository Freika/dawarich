import { MapHook } from "./map.js"
export const TripHook = {
  ...MapHook,
  loader: () =>
    import("../trip/runtime.js").then((module) => ({
      mountHost: module.mountTrip,
    })),
  async mounted() {
    this.tripDay = undefined
    this.tripDayPending = false
    this.tripDayHandler = this.handleEvent(
      "trip:select_day",
      ({ day, expanded = false }) => {
        if (this.mapDestroyed || this.mapRevoked) return
        if (
          day !== null &&
          (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day))
        )
          return
        const days =
          this.el
            .closest?.("[data-native-map-root]")
            ?.querySelectorAll('details[id^="native-trip-day-"]') ?? []
        for (const detail of days)
          detail.open =
            expanded === true || detail.id === `native-trip-day-${day}`
        this.tripDay = day
        this.tripDayPending = !this.mapReady
        if (this.mapReady) this.mapOwner?.layers?.selectDay?.(day)
      },
    )
    this.tripFocus = undefined
    this.tripFocusPending = false
    this.tripFocusHandler = this.handleEvent(
      "trip:focus",
      ({ longitude, latitude }) => {
        if (this.mapDestroyed || this.mapRevoked) return
        if (
          !Number.isFinite(longitude) ||
          !Number.isFinite(latitude) ||
          longitude < -180 ||
          longitude > 180 ||
          latitude < -90 ||
          latitude > 90
        )
          return
        this.tripFocus = { longitude, latitude }
        this.tripFocusPending = !this.mapReady
        if (this.mapReady)
          this.mapOwner?.layers?.focusPlan?.(longitude, latitude)
      },
    )
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
    if (
      this.mapReady &&
      !this.mapDestroyed &&
      !this.mapRevoked &&
      this.tripFocusPending
    ) {
      this.tripFocusPending = false
      this.mapOwner?.layers?.focusPlan?.(
        this.tripFocus.longitude,
        this.tripFocus.latitude,
      )
    }
  },
  destroyed() {
    if (this.tripDayHandler !== null && this.tripDayHandler !== undefined)
      this.removeHandleEvent(this.tripDayHandler)
    this.tripDayHandler = null
    this.tripDay = undefined
    this.tripDayPending = false
    if (this.tripFocusHandler !== null && this.tripFocusHandler !== undefined)
      this.removeHandleEvent(this.tripFocusHandler)
    this.tripFocusHandler = null
    this.tripFocus = undefined
    this.tripFocusPending = false
    MapHook.destroyed.call(this)
  },
}
