import { MapHook } from "./map.js"
export const FamilyHook = {
  ...MapHook,
  async mounted() {
    this.familyLease = null
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
    this.mapOwner?.clear?.()
  },
  destroyed() {
    for (const ref of this.familyHandlers ?? []) this.removeHandleEvent(ref)
    this.familyHandlers = []
    MapHook.destroyed.call(this)
  },
  loader: () =>
    import("../family/runtime.js").then(({ mountFamily }) => ({
      mountHost: mountFamily,
    })),
}
