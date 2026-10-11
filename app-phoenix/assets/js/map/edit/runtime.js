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
  timers = globalThis,
  timeoutMs = 15000,
  onUncertain = () => {},
}) {
  let destroyed = false
  const pending = new Set()

  function send(pointId, position, { pointRevision, trackRevision, scope }) {
    return new Promise((resolve, reject) => {
      const request = { reject, timer: null }
      const finish = (error, response) => {
        if (!pending.delete(request)) return
        timers.clearTimeout(request.timer)
        if (error) reject(error)
        else resolve(response)
      }
      pending.add(request)
      request.timer = timers.setTimeout(() => {
        const error = new Error("Point command timed out")
        error.name = "TimeoutError"
        finish(error)
        try {
          onUncertain(pointId)
        } catch {}
      }, timeoutMs)
      try {
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
            if (destroyed || !pending.has(request)) return
            if (reply?.ok) return finish(null, reply.response)
            const error = new Error(reply?.error || "move_failed")
            error.status = reply?.error === "stale" ? 409 : 422
            error.payload = reply?.response
            finish(error)
          },
        )
      } catch (error) {
        finish(error)
      }
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

  function cancel() {
    for (const request of pending) {
      timers.clearTimeout(request.timer)
      request.reject(abortError())
    }
    pending.clear()
  }

  function destroy() {
    if (destroyed) return
    destroyed = true
    gesture?.detach()
    cancel()
  }

  return {
    commit,
    move: (pointId, step) =>
      destroyed || !isEditMode()
        ? Promise.reject(abortError())
        : send(pointId, step, {
            ...step,
            scope: step.historyScope ?? historyScope(),
          }),
    undo: () => (destroyed ? Promise.reject(abortError()) : history.undo()),
    redo: () => (destroyed ? Promise.reject(abortError()) : history.redo()),
    cancel,
    destroy,
    history,
  }
}
