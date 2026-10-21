import { mapTranslate } from "../ui/translate.js"

export function installMapRetry({ owner, root, layers, density, loader = () => import("../ui/retry.js") }) {
  let loading, retry, cleanup, destroyed = false
  const document = root?.ownerDocument
  if (document?.defaultView) import("../ui/feedback.js").then(({ installMapFeedback }) => {
    if (!destroyed) cleanup = installMapFeedback({ owner, root })
  })
  const destroy = owner.destroy
  owner.destroy = () => {
    destroyed = true
    cleanup?.()
    retry?.destroy()
    destroy.call(owner)
  }
  const load = () => loading ??= loader().then(({ createMapRetry }) => {
    if (destroyed) return
    retry = createMapRetry({
      root, translate: mapTranslate(() => owner.config),
      async run(code) {
        if (code === "point_tiles_failed") return layers()?.points.retry()
        if (code === "track_tiles_failed") return layers()?.tracks.retry()
        if (code.startsWith("scratch")) return density()?.retry(code)
        return owner.reconnect({ kinds: ["retry"] })
      },
    })
  })
  return {
    notice: async (...args) => {
      const { mapNotify } = await import("../ui/notify.js")
      if (!destroyed) mapNotify(() => owner.config)(...args)
    },
    async fail(code, bindings) {
      if (destroyed) return
      try { await load(); if (!destroyed) retry.fail(code, bindings) }
      catch { loading = null }
    },
  }
}
