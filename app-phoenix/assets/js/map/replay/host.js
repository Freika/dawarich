import { createReplay } from "./runtime.js"
import { createReplayPanel } from "./panel.js"
import { mapTranslate } from "../ui/translate.js"

export function installHostReplay({ owner, map, lifetime, root }) {
  let runtime = null, panel = null, range = null, active = false, latest = {}
  const translate = mapTranslate(() => owner.config)
  const keys = ["play", "speed", "speedLabel", "prev", "next", "day", "dayCount", "time", "velocity", "noData", "follow", "scrubber"]
  const elements = Object.fromEntries(keys.map(key => [key, root?.querySelector(`[data-replay="${key}"]`)]))
  const container = root?.querySelector("[data-map-replay-panel]")
  const opener = root?.querySelector("[data-map-replay-open]")
  function ensure() {
    runtime ??= createReplay({map, timezone: owner.config.range.timezone,
      loadDay: async (_range, {signal}) => (await owner.source.snapshot({purpose: "replay", signal})).points,
      onState: state => { latest = state; panel?.onState(state) },
      onPoint: point => panel?.onState({point}), onStop: () => panel?.stopped(),
      onFollow: enabled => elements.follow?.setAttribute("aria-pressed", String(enabled)),
    })
    runtime.manager.translate = translate
    runtime.manager.locale = owner.config.locale ?? "en"
    return runtime
  }
  owner.replay = {
    async open(next = owner.config.range) {
      active = true
      range = JSON.stringify(next)
      try {
        const result = await ensure().open(next)
        if (result !== "ready" || !active) return result
        if (container) container.hidden = false
        panel?.destroy()
        if (keys.every(key => elements[key])) panel = createReplayPanel({elements, replay: runtime, translate})
        panel?.onState(latest)
        return result
      } catch (error) { if (error.name !== "AbortError") throw error; return "cancelled" }
    },
    close() { active = false; panel?.destroy(); panel = null; runtime?.close(); if (container) container.hidden = true },
    play: () => ensure().play(), pause: () => runtime?.pause(),
    seek: minute => runtime?.seek(minute), setSpeed: speed => runtime?.setSpeed(speed),
    recenter: position => runtime?.recenter(position),
    get manager() { return runtime?.manager }, get playing() { return runtime?.playing ?? false },
  }
  const open = () => { owner.replay.open().catch(() => owner.replay.close()) }
  const close = () => { owner.replay.close(); opener?.focus() }
  const closer = root?.querySelector("[data-map-replay-close]")
  opener?.addEventListener("click", open)
  closer?.addEventListener("click", close)
  const update = owner.update, reconnect = owner.reconnect
  owner.update = async next => {
    const changed = active && range !== JSON.stringify(next.range)
    if (changed) runtime?.close()
    if (next.panel && next.panel !== "replay") owner.replay.close()
    const result = await update.call(owner, next)
    if (changed && active) await owner.replay.open(next.range)
    return result
  }
  owner.reconnect = async () => { const result = await reconnect.call(owner); runtime?.reconnect(); return result }
  lifetime.own(() => { opener?.removeEventListener("click", open); closer?.removeEventListener("click", close); owner.replay.close() })
  return owner.replay
}
