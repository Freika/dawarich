import { Toast } from "./toast.js"

export function createMapRetry({ root, translate, run }) {
  let current, destroyed = false
  function fail(code, bindings = {}) {
    if (code === "areas_load_failed" && root?.dataset.areaReloadPending) code = "areas_reload_failed"
    const message = {
      areas_reload_failed: ["error", "messages.failed_to_reload_areas"],
      selection_refresh_failed: ["error", "selection.map_refresh_failed"],
      map_refresh_failed: ["error", "messages.failed_to_load_location_data_please_try_again"],
      photos_load_failed: ["error", "messages.failed_to_load_photos"],
      photo_sources_partial: ["warning", "messages.some_photo_sources_unavailable"],
      photos_unconfigured: ["error", "messages.failed_to_load_photos"],
      areas_load_failed: ["error", "messages.failed_to_load_areas"],
      flights_load_failed: ["error", "messages.failed_to_load_flights"],
      anomalies_load_failed: ["error", "messages.failed_to_load_anomalies"],
      hexagons_load_failed: ["error", "hexagons.load_failed"],
      hexagons_limit: ["warning", "hexagons.limit_warning"],
    }[code]
    if (message && !destroyed && root?.ownerDocument?.body)
      return Toast[message[0]](translate(message[1], bindings))
    if (destroyed || !root?.ownerDocument?.body) return
    if (current?.code === code) return
    if (current) Toast.dismiss(current.node)
    const key = code.startsWith("scratch")
      ? "messages.failed_to_load_visited_countries" : "messages.failed_to_load_map_tiles"
    const entry = { code }
    entry.node = Toast.retry(translate(key), translate("messages.retry"), async () => {
      if (destroyed || current !== entry) return
      current = null
      try {
        const result = await run(code)
        if (result === "failed") fail(code)
      } catch { fail(code) }
    })
    current = entry
  }
  return { fail, destroy() { destroyed = true; if (current) Toast.dismiss(current.node); current = null } }
}
