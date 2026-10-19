const scoped = new Set([
  "points",
  "tracks",
  "family",
  "imports",
  "progress",
  "sharing",
])

export function installRealtimeActions(owner, parts) {
  const reconnect = owner.reconnect
  owner.reconnect = async (batch) => {
    const kinds = new Set(batch?.kinds ?? [])
    if (kinds.size === 0 || [...kinds].some((kind) => !scoped.has(kind)))
      return reconnect.call(owner, batch)
    const { layers, density, family, recent } = parts()
    const points = kinds.has("points")
    if (points) {
      recent?.prepare({ kinds: ["points"] })
      layers?.points.refresh()
      density?.invalidate()
      await density?.update(owner.config)
    }
    if (kinds.has("tracks")) layers?.tracks.refresh()
    if (kinds.has("family")) await family?.update(owner.config)
    if (points) await recent?.deliver({ kinds: ["points"] })
    return "ready"
  }
}
