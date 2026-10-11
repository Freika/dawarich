import { MapHook } from "./map.js"
export const FamilyHook = {
  ...MapHook,
  async mounted() {
    this.familyLease = null
    this.familyWindow = this.el.ownerDocument?.defaultView
    this.familyOffline = this.familyWindow?.navigator?.onLine === false
    this.familyOnOffline = () => this.disconnected()
    this.familyOnOnline = () => this.reconnected()
    this.familyWindow?.addEventListener("offline", this.familyOnOffline)
    this.familyWindow?.addEventListener("online", this.familyOnOnline)
    this.familyHandlers = [
      this.handleEvent("family:lease", (receipt) => {
        this.familyLease = receipt
        this.mapOwner?.lease?.(receipt)
      }),
      this.handleEvent("family:clear", () => this.mapOwner?.clear?.()),
    ]
    await MapHook.mounted.call(this)
    if (!this.mapDestroyed && !this.mapRevoked && this.familyLease)
      this.mapOwner?.lease?.(this.familyLease)
  },
  disconnected() {
    this.familyOffline = true
    this.mapInvalidations = []
    this.mapOwner?.clear?.()
  },
  reconnected() {
    this.familyOffline = false
    return MapHook.reconnected.call(this)
  },
  destroyed() {
    this.familyWindow?.removeEventListener("offline", this.familyOnOffline)
    this.familyWindow?.removeEventListener("online", this.familyOnOnline)
    for (const ref of this.familyHandlers ?? []) this.removeHandleEvent(ref)
    this.familyHandlers = []
    MapHook.destroyed.call(this)
  },
  loader() {
    return import("../family/runtime.js").then(({ mountFamily }) => ({
      mountHost: (options) => mountFamily({
        ...options, isOffline: () => this.familyOffline,
      }),
    }))
  },
}
