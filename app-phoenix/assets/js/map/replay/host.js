import { bindTool } from "../ui/host_tools.js"
import { mapTranslate } from "../ui/translate.js"
import { createReplayDensity } from "./density.js"
import { createReplayPanel } from "./panel.js"
import { createReplay } from "./runtime.js"

export function installHostReplay({
  owner,
  map,
  lifetime,
  root,
  library,
  reader,
  onActive = () => {},
}) {
  let runtime = null,
    panel = null,
    density = null,
    photos = null,
    photoRows = [],
    range = null,
    active = false,
    latest = {},
    generation = 0
  const translate = mapTranslate(() => owner.config)
  const keys = [
    "play",
    "speed",
    "speedLabel",
    "prev",
    "next",
    "day",
    "dayCount",
    "time",
    "velocity",
    "noData",
    "follow",
    "scrubber",
  ]
  const elements = Object.fromEntries(
    [...keys, "cycle", "cyclePrev", "cycleNext", "cycleCount"].map((key) => [
      key,
      root?.querySelector(`[data-replay="${key}"]`),
    ]),
  )
  const container = root?.querySelector("[data-map-replay-panel]")
  function ensure() {
    if (runtime && runtime.manager.timezone !== owner.config.range.timezone) {
      runtime.close()
      runtime = null
    }
    runtime ??= createReplay({
      map,
      timezone: owner.config.range.timezone,
      loadDay: async (_range, { signal }) => {
        const snapshot = await owner.source.snapshot({
          purpose: "replay",
          signal,
        })
        photoRows = snapshot.photos ?? []
        return snapshot.points
      },
      onState: (state) => {
        const changed = latest.day !== state.day
        latest = state
        if (changed) density?.render()
        panel?.onState(state)
      },
      onPoint: (point) => {
        panel?.onState({ point })
        photos?.sync(point)
      },
      onStop: () => panel?.stopped(),
      onFollow: (enabled) =>
        elements.follow?.setAttribute("aria-pressed", String(enabled)),
    })
    runtime.manager.noDataLabel = translate("replay.no_data_loaded")
    runtime.manager.locale = owner.config.locale ?? "en"
    return runtime
  }
  owner.replay = {
    async open(next = owner.config.range) {
      owner.replay.close()
      if (lifetime.destroyed) return "cancelled"
      const current = generation
      active = true
      onActive(true)
      range = JSON.stringify(next)
      try {
        const result = await ensure().open(next)
        if (result !== "ready" || !active) return result
        const photoModule = library?.Marker ? await import("./photos.js") : null
        if (!active || current !== generation || lifetime.destroyed)
          return "cancelled"
        if (container) container.hidden = false
        panel?.destroy()
        if (keys.every((key) => elements[key]))
          panel = createReplayPanel({ elements, replay: runtime, translate })
        panel?.onState(latest)
        density?.destroy()
        photos?.destroy()
        const densityRoot = root?.querySelector("[data-replay-density]")
        if (densityRoot)
          density = createReplayDensity({
            container: densityRoot,
            document: root.ownerDocument,
            manager: runtime.manager,
            seek: (minute) => runtime.seek(minute),
          })
        if (library?.Marker)
          photos = photoModule.createReplayPhotos({
            photos: photoRows,
            map,
            library,
            reader,
            document: root?.ownerDocument ?? map.getContainer().ownerDocument,
            container: root?.querySelector("[data-replay-photos]"),
            manager: runtime.manager,
            labels: owner.config.photoLabels,
          })
        runtime.seek(latest.minute ?? 0)
        return result
      } catch (error) {
        if (error.name !== "AbortError") throw error
        return "cancelled"
      }
    },
    close() {
      generation++
      active = false
      if (!lifetime.destroyed) onActive(false)
      panel?.destroy()
      panel = null
      density?.destroy()
      density = null
      photos?.destroy()
      photos = null
      runtime?.close()
      if (container) container.hidden = true
    },
    play: () => ensure().play(),
    pause: () => runtime?.pause(),
    seek: (minute) => runtime?.seek(minute),
    setSpeed: (speed) => runtime?.setSpeed(speed),
    recenter: (position) => runtime?.recenter(position),
    get active() {
      return active
    },
    get manager() {
      return runtime?.manager
    },
    get playing() {
      return runtime?.playing ?? false
    },
  }
  const open = () => {
    if (active) owner.replay.close()
    else owner.replay.open().catch(() => owner.replay.close())
  }
  const close = () => {
    owner.replay.close()
    root?.querySelector("[data-map-replay-open]")?.focus()
  }
  bindTool(root, "[data-map-replay-open]", open, lifetime)
  bindTool(root, "[data-map-replay-close]", close, lifetime)
  const update = owner.update,
    reconnect = owner.reconnect
  owner.update = async (next) => {
    const changed = active && range !== JSON.stringify(next.range)
    if (changed) owner.replay.close()
    const result = await update.call(owner, next)
    if (changed && result === "ready") await owner.replay.open(next.range)
    return result
  }
  owner.reconnect = async (receipt) => {
    const result = await reconnect.call(owner, receipt)
    runtime?.reconnect()
    return result
  }
  lifetime.own(() => {
    owner.replay.close()
  })
  return owner.replay
}
