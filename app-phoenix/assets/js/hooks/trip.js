import { MapHook } from "./map.js"
export const TripHook = {
  ...MapHook,
  loader: () =>
    import("../map/trip/runtime.js").then(({ mountTrip }) => ({
      mountHost: mountTrip,
    })),
}
