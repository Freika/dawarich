import { createRequestScope } from "../data/request_scope.js"
import { createTimelineHover } from "./timeline.js"
import { createTrackSelection } from "./track_selection.js"

export function createHostTimeline({
  map,
  root,
  reader,
  lifetime,
  library,
  pushEvent,
  getConfig,
  replay,
  blocked = () => false,
}) {
  const selection = createTrackSelection({
    map,
    reader,
    root,
    library,
    getConfig,
  })
  const hover = createTimelineHover({ map })
  const requests = createRequestScope()
  let hovered
  let selected
  function clear() {
    hovered?.setAttribute("data-track-hovered", "false")
    hovered?.classList?.remove("bg-base-200")
    hovered = null
    selected = null
    requests.reset()
    hover.clear()
  }
  async function enter(event) {
    const id = event.target.closest?.("[data-track-id]")?.dataset.trackId
    if (!id || selected === id) return
    clear()
    selected = id
    const operation = requests.begin()
    try {
      const result = await operation.wait(
        reader.read("track", { id }, { signal: operation.signal }),
      )
      operation.check()
      hover.hover(result.data)
    } catch {
    } finally {
      operation.close()
    }
  }
  function click(event) {
    if (blocked()) return
    const available = [
      "tracks-mvt",
      "native-selected-track-line",
      "native-selected-track-segments",
    ].filter((id) => map.getLayer(id))
    const features = available.length
      ? map.queryRenderedFeatures?.(event.point, { layers: available }) || []
      : []
    const feature = features.find((feature) =>
      Number.isSafeInteger(
        Number(feature.properties?.track_id || feature.properties?.id),
      ),
    )
    const id = Number(feature?.properties?.track_id || feature?.properties?.id)
    if (id > 0) pushEvent("map:select", { kind: "track", id })
    else pushEvent("track:close", {})
  }
  async function replayClick(event) {
    const control = event.target.closest?.("[data-track-replay]")
    if (!control) return
    const time = new Date(control.dataset.trackStart)
    if (!Number.isFinite(time.getTime())) return
    const current = replay()
    if (current.playing) return current.pause()
    if (current.active && current.manager.hasData()) return current.play()
    if (!current.active && (await current.open()) !== "ready") return
    if (!current.manager.hasData()) return
    const day = new Intl.DateTimeFormat("en-CA", {
      timeZone: getConfig().range.timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(time)
    current.manager.goToDay(day)
    current.seek(current.manager.minuteOfDay(time))
    current.play()
  }
  function move(event) {
    if (blocked()) return leave()
    const available = ["tracks-mvt", "native-selected-track-segments"].filter(
      (id) => map.getLayer(id),
    )
    const features = available.length
      ? map.queryRenderedFeatures?.(event.point, { layers: available }) || []
      : []
    const feature = features[0]
    const id = Number(feature?.properties?.track_id || feature?.properties?.id)
    if (!Number.isSafeInteger(id) || id <= 0) return leave()
    map.getCanvas().style.cursor = "pointer"
    enter({ target: { closest: () => ({ dataset: { trackId: String(id) } }) } })
    hovered = root?.querySelector(`[data-track-id="${id}"]`)
    hovered?.setAttribute("data-track-hovered", "true")
    hovered?.classList?.add("bg-base-200")
  }
  function leave() {
    clear()
    map.getCanvas().style.cursor = ""
  }
  map.on("mousemove", move)
  map.on("mouseleave", leave)
  const play = (event) => {
    replayClick(event).catch(() => {})
  }
  map.on("click", click)
  root?.addEventListener("click", play)
  root?.addEventListener("pointerover", enter)
  root?.addEventListener("pointerout", clear)
  lifetime.own(() => {
    root?.removeEventListener("pointerover", enter)
    root?.removeEventListener("pointerout", clear)
    map.off("mousemove", move)
    map.off("mouseleave", leave)
    map.off("click", click)
    root?.removeEventListener("click", play)
    selection.destroy()
    requests.destroy()
    hover.destroy()
  })
  return {
    select: selection.select,
    config() {
      clear()
      selection.clear()
    },
  }
}
