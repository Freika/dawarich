const full = new Set(["map", "reconnect", "trip", "public"])

export function installRealtimeActions(owner, parts) {
  owner.realtime = async (batch = {}) => {
    const kinds = new Set(batch.kinds ?? [])
    if ([...kinds].some((kind) => full.has(kind))) return owner.reconnect(batch)
    const { layers, density, family, recent, editing, editor } = parts()
    const edits = kinds.has("map_edits"),
      points = kinds.has("points"),
      tracks = kinds.has("tracks") || edits
    if (edits) await editing?.reconcile(batch)
    if (points) recent?.prepare({ kinds: ["points"] })
    if (points || edits) {
      layers?.points.refresh()
      density?.invalidate()
      await density?.update(owner.config)
    }
    if (tracks) {
      layers?.tracks.refresh()
      editor?.reapplyTileFilters?.()
    }
    if (kinds.has("family")) await family?.update(owner.config)
    if (points) await recent?.deliver({ kinds: ["points"] })
    return "ready"
  }
}
