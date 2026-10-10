import { createReplay } from "./runtime.js"

export function installHostReplay({ owner, map, lifetime }) {
  let runtime = null
  let range = null
  let active = false
  function ensure() {
    runtime ??= createReplay({map, timezone: owner.config.range.timezone,
      loadDay: async (_range, {signal}) => (await owner.source.snapshot({purpose: "replay", signal})).points,
    })
    return runtime
  }
  owner.replay = {
    async open(next = owner.config.range) {
      active = true
      range = JSON.stringify(next)
      try { return await ensure().open(next) } catch (error) { if (error.name !== "AbortError") throw error; return "cancelled" }
    },
    close() { active = false; runtime?.close() },
    play: () => ensure().play(), pause: () => runtime?.pause(),
    seek: minute => runtime?.seek(minute), setSpeed: speed => runtime?.setSpeed(speed),
    recenter: position => runtime?.recenter(position),
    get manager() { return runtime?.manager }, get playing() { return runtime?.playing ?? false },
  }
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
  lifetime.own(() => owner.replay.close())
  return owner.replay
}
