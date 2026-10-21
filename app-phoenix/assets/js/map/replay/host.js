import { bindTool } from "../ui/host_tools.js"
import { mapTranslate } from "../ui/translate.js"

export function installHostReplay({
  owner,
  map,
  lifetime,
  root,
  library,
  reader,
  onActive = () => {},
}) {
  let controls = null
  let runtime = null,
    panel = null,
    density = null,
    photos = null,
    photoRows = [],
    range = null,
    active = false,
    latest = {},
    generation = 0,
    reopening = false,
    stack = null
  const photoStack = () => {
    const parent = map.getContainer?.()
    if (!parent || stack) return stack
    stack = parent.ownerDocument.createElement("div")
    stack.className = "replay-photo-stack"
    parent.appendChild(stack)
    return stack
  }
  const translate = mapTranslate(() => owner.config)
  const targets = {
    play: "replayPlayButton",
    speed: "replaySpeedSlider",
    speedLabel: "replaySpeedLabel",
    day: "replayDayDisplay",
    dayCount: "replayDayCount",
    time: "replayTimeDisplay",
    velocity: "replaySpeedDisplay",
    noData: "replayDataIndicator",
    follow: "replayFollowButton",
    scrubber: "replayScrubber",
    prev: "replayPrevDayButton",
    next: "replayNextDayButton",
    cycle: "replayCycleControls",
    cycleCount: "replayPointCounter",
    playIcon: "replayPlayIcon",
    pauseIcon: "replayPauseIcon",
  }
  const keys = Object.keys(targets).slice(0, 10)
  const find = (selector) => root?.querySelector(selector)
  const elements = {
    ...Object.fromEntries(
      Object.entries(targets).map(([key, name]) => [
        key,
        find(`[data-native-replay-target="${name}"]`),
      ]),
    ),
    cyclePrev: find('[data-native-replay-action="replayCyclePrev"]'),
    cycleNext: find('[data-native-replay-action="replayCycleNext"]'),
  }
  const container = find("[data-native-replay-panel]")
  const show = (visible) => {
    if (!container) return
    container.hidden = !visible
    container.classList?.toggle("hidden", !visible)
  }
  function ensure() {
    if (runtime && runtime.manager.timezone !== owner.config.range.timezone) {
      runtime.close()
      runtime = null
    }
    runtime ??= controls.createReplay({
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
        controls ??= await import("./controls.js")
        if (!active || current !== generation || lifetime.destroyed) return "cancelled"
        const result = await ensure().open(next)
        if (result !== "ready" || !active) return result
        const photoModule = library?.Marker ? await import("./photos.js") : null
        if (!active || current !== generation || lifetime.destroyed)
          return "cancelled"
        show(true)
        panel?.destroy()
        if (keys.every((key) => elements[key]))
          panel = controls.createReplayPanel({ elements, replay: runtime, translate })
        panel?.onState(latest)
        density?.destroy()
        photos?.destroy()
        const densityRoot = find(
          '[data-native-replay-target="replayDensityContainer"]',
        )
        if (densityRoot)
          density = controls.createReplayDensity({
            container: densityRoot,
            document: root.ownerDocument,
            manager: runtime.manager,
          })
        if (library?.Marker)
          photos = photoModule.createReplayPhotos({
            photos: photoRows,
            map,
            library,
            reader,
            document: root?.ownerDocument ?? map.getContainer().ownerDocument,
            container: photoStack(),
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
      reopening = false
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
      stack?.remove()
      stack = null
      show(false)
    },
    play: () => runtime?.play(),
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
  bindTool(root, '[data-native-replay-action="toggleReplay"]', close, lifetime)
  const update = owner.update,
    reconnect = owner.reconnect
  owner.update = async (next) => {
    const changed =
      (active || reopening) && range !== JSON.stringify(next.range)
    if (changed) {
      owner.replay.close()
      reopening = true
    }
    const result = await update.call(owner, next)
    if (reopening && result === "ready") await owner.replay.open(next.range)
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
