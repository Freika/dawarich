import { MapHook } from "./map.js"
export const FamilyHook = {
  ...MapHook,
  loader: () =>
    import("../map/family/runtime.js").then(({ mountFamily }) => ({
      mountHost: mountFamily,
    })),
}
