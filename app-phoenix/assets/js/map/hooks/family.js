import { MapHook } from "./map.js"
export const FamilyHook = {
  ...MapHook,
  async mounted() {
    this.familyLease = null
    this.familyRefs = [
      this.handleEvent("family:lease", (receipt) => {
        this.familyLease = receipt
        this.mapOwner?.lease?.(receipt)
      }),
      this.handleEvent("family:clear", () => this.mapOwner?.clear?.()),
    ]
    await MapHook.mounted.call(this)
    if (this.familyLease) this.mapOwner?.lease?.(this.familyLease)
  },
  disconnected() {
    this.mapOwner?.clear?.()
  },
  destroyed() {
    for (const ref of this.familyRefs ?? []) this.removeHandleEvent(ref)
    this.familyRefs = []
    MapHook.destroyed.call(this)
  },
  loader: () =>
    import("../family/runtime.js").then(({ mountFamily }) => ({
      mountHost: mountFamily,
    })),
}
