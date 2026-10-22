const HISTORY_LIMIT = 5

// Undo/redo for point moves made in this page. Every step is a regular move
// sent with the newest point and track revisions seen in any response, so a
// step loses cleanly (409) to an edit made elsewhere; that step is dropped.
export class PointEditHistory {
  constructor({ move, onChange = () => {} }) {
    this.move = move
    this.onChange = onChange
    this.entries = []
    this.undone = []
    this.busy = false
    this.pointRevisions = new Map()
    this.trackRevisions = new Map()
  }

  get limit() {
    return HISTORY_LIMIT
  }

  get size() {
    return this.entries.length + this.undone.length
  }

  get canUndo() {
    return !this.busy && this.entries.length > 0
  }

  get canRedo() {
    return !this.busy && this.undone.length > 0
  }

  record({ pointId, from, to }, response) {
    this._remember(response)
    const trackId = response.track?.properties?.id
    this.entries.push({
      pointId: Number(pointId),
      trackId: trackId == null ? null : Number(trackId),
      from,
      to,
      at: Date.now(),
    })
    if (this.entries.length > HISTORY_LIMIT) this.entries.shift()
    this.undone = []
    this.onChange()
  }

  undo() {
    return this._step(this.entries, this.undone, "from")
  }

  redo() {
    return this._step(this.undone, this.entries, "to")
  }

  async travelTo(entry) {
    const [source, step] = this.entries.includes(entry)
      ? [this.entries, () => this.undo()]
      : [this.undone, () => this.redo()]
    while (source.includes(entry)) {
      if (!(await step())) return
    }
  }

  async _step(source, target, positionKey) {
    const entry = source.at(-1)
    if (this.busy || !entry) return null

    this.busy = true
    this.onChange()
    try {
      const response = await this.move(entry.pointId, {
        ...entry[positionKey],
        pointRevision: this.pointRevisions.get(entry.pointId) ?? 0,
        trackRevision:
          entry.trackId == null
            ? null
            : (this.trackRevisions.get(entry.trackId) ?? null),
      })
      this._remember(response)
      source.pop()
      target.push(entry)
      return response
    } catch (error) {
      if (error.status === 409) {
        source.pop()
        if (error.payload?.point) this._remember(error.payload)
      }
      throw error
    } finally {
      this.busy = false
      this.onChange()
    }
  }

  _remember(response) {
    const point = response?.point
    if (!point) return
    this.pointRevisions.set(
      Number(point.id),
      Number(response.revision?.point ?? point.revision ?? 0),
    )
    const trackId = response.track?.properties?.id
    if (trackId != null)
      this.trackRevisions.set(
        Number(trackId),
        Number(
          response.revision?.track ?? response.track.properties.revision ?? 0,
        ),
      )
  }
}
