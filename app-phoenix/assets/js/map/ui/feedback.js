import { mapNotify } from "./notify.js"
import { installLayerPreviews } from "./layer_previews.js"

export function installMapFeedback({ owner, root }) {
  let destroyed = false
  const notify = mapNotify(() => owner.config)
  const window = root.ownerDocument.defaultView
  const receipt = ({ detail }) => {
    if (detail?.key === "messages.area_created_successfully") root.dataset.areaReloadPending = "true"
    if (!destroyed && ["info", "success", "error", "warning"].includes(detail?.type))
      notify(detail.type, detail.key, detail.bindings)
  }
  window.addEventListener("phx:map:toast", receipt)
  owner.connectionToast = connected => {
    if (!destroyed) notify(connected ? "success" : "warning", connected ? "messages.connected_to_real_time_updates" : "messages.disconnected_from_real_time_updates")
  }
  owner.connectionToast(true)
  const stop = installLayerPreviews({ owner, root: root.closest?.("[data-native-map-root]") })
  return () => {
    destroyed = true
    window.removeEventListener("phx:map:toast", receipt)
    stop()
  }
}
