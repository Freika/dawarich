import { createLocationSearch } from "../data/location_search.js"
import { createRequestScope } from "../data/request_scope.js"
import { panelPadding } from "./padding.js"
import { createSearchUi } from "./search.js"
import { fitRoute } from "./search_results.js"
import { createVisitResults } from "./search_visits.js"
import { mapTranslate } from "./translate.js"

export function createHostSearch({
  map,
  root,
  reader,
  lifetime,
  document,
  pushEvent,
  getConfig,
}) {
  const search = createLocationSearch({ reader })
  const container = root?.querySelector("[data-map-search-visits]")
  const visits = container
    ? createVisitResults({
        container,
        document,
        search,
        translate: mapTranslate(getConfig),
        timezone: () => getConfig().range.timezone,
        flyTo: ({ lat, lon, zoom }) => map.flyTo({ center: [lon, lat], zoom }),
        pushEvent,
      })
    : null
  if (visits) lifetime.own(visits.destroy)
  const input = root?.querySelector("[data-map-search]")
  const results = root?.querySelector("[data-map-suggestions]")
  if (input && results) {
    const ui = createSearchUi({
      input,
      results,
      document,
      search,
      onSelect: (item) =>
        visits
          ? visits.open(item)
          : map.flyTo({ center: [item.lon, item.lat] }),
      onCancel: () => visits?.clear(),
    })
    lifetime.own(ui.destroy)
  }
  const scope = createRequestScope()
  const padding = panelPadding({
    container: map.getContainer?.(),
    overlay: () => root?.querySelector("#native-map-panel"),
  })
  const click = async (event) => {
    const id = event.target.closest?.("[data-track-id]")?.dataset.trackId
    if (!id) return
    const operation = scope.begin()
    try {
      const { data } = await operation.wait(
        reader.read("track", { id }, { signal: operation.signal }),
      )
      operation.check()
      fitRoute({ map, geometry: data.geometry, padding })
    } catch {
    } finally {
      operation.close()
    }
  }
  root?.addEventListener("click", click)
  lifetime.own(() => {
    root?.removeEventListener("click", click)
    scope.destroy()
    search.cancel()
  })
  return { search, results: visits }
}
