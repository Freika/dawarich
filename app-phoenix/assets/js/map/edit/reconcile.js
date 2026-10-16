export function createEditReconciliation({ editor, readTrack, reset, invalidate }) {
  let saved
  return {
    remember(response) {
      saved = response.track && {
        id: Number(response.track.properties.id),
        revision: Number(response.revision?.track),
        session: editor.sessionVersion,
      }
    },
    async reconcile(receipt) {
      if (receipt?.kinds?.includes("reconnect") || !saved || editor.inFlight ||
          editor.trackId !== saved.id || editor.sessionVersion !== saved.session || !editor.data)
        return invalidate()
      const current = saved
      reset()
      try {
        const track = await readTrack(current.id)
        if (editor.sessionVersion !== current.session) return
        if (Number(track.properties.revision) === current.revision) return
      } catch {}
      if (editor.sessionVersion === current.session) invalidate()
    },
  }
}
