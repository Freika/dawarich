import { PointEditHistory } from "./history.js"

const abortError = () => {
  const error = new Error("Point editing closed")
  error.name = "AbortError"
  return error
}

export function createPointEditing({
  isEditMode,
  pushEvent,
  setPosition,
  gesture = null,
  historyScope = () => ({}),
}) {
  let destroyed = false
  const pending = new Set()

  function send(pointId, position, { pointRevision, trackRevision, scope }) {
    return new Promise((resolve, reject) => {
      const request = { reject }
      pending.add(request)
      pushEvent(
        "point:move",
        {
          point_id: pointId,
          point: {
            latitude: String(position.latitude),
            longitude: String(position.longitude),
            revision: pointRevision,
          },
          track_revision: trackRevision,
          history_scope: { start_at: scope.startAt, end_at: scope.endAt },
        },
        (reply) => {
          if (!pending.delete(request) || destroyed) return
          if (reply?.ok) return resolve(reply.response)
          const error = new Error(reply?.error || "move_failed")
          error.status = reply?.error === "stale" ? 409 : 422
          error.payload = reply?.response
          reject(error)
        },
      )
    })
  }

  const history = new PointEditHistory({
    move: (pointId, step) =>
      send(pointId, step, { ...step, scope: historyScope() }),
  })

  async function commit({
    pointId,
    from,
    to,
    pointRevision,
    trackRevision,
    historyScope: scope,
  }) {
    if (destroyed || !isEditMode()) {
      if (!destroyed) setPosition(pointId, from)
      return { status: "refused" }
    }
    try {
      const response = await send(pointId, to, {
        pointRevision,
        trackRevision,
        scope,
      })
      history.record({ pointId, from, to }, response)
      return { status: "saved" }
    } catch (error) {
      if (destroyed || error.name === "AbortError")
        return { status: "cancelled" }
      setPosition(pointId, from)
      if (error.status === 409 && error.payload?.point)
        history._remember(error.payload)
      return { status: error.status === 409 ? "conflict" : "error" }
    }
  }

  function destroy() {
    if (destroyed) return
    destroyed = true
    gesture?.detach()
    for (const request of pending) request.reject(abortError())
    pending.clear()
  }

  return {
    commit,
    undo: () => (destroyed ? Promise.reject(abortError()) : history.undo()),
    redo: () => (destroyed ? Promise.reject(abortError()) : history.redo()),
    destroy,
    history,
  }
}
