import { MapHook } from "./map.js"
export const PublicMap = {
  ...MapHook,
  loader: () =>
    import("../map/public/runtime.js").then((module) => ({
      mountHost: module.mountPublic,
    })),
}
