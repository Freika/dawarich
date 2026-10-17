import { mapTranslate } from "../ui/translate.js"

export function installMapRetry({ owner, root, layers, density, loader = () => import("../ui/retry.js") }) {
  let loading, retry, destroyed = false
  const destroy = owner.destroy
  owner.destroy = () => {
    destroyed = true
    retry?.destroy()
    destroy.call(owner)
  }
  return {
    async fail(code) {
      if (destroyed) return
      loading ??= loader().then(({ createMapRetry }) => {
        if (destroyed) return
        retry = createMapRetry({
          root,
          translate: mapTranslate(() => owner.config),
          async run(code) {
            if (code === "point_tiles_failed") return layers()?.points.retry()
            if (code === "track_tiles_failed") return layers()?.tracks.retry()
            if (code.startsWith("scratch")) return density()?.retry(code)
            return owner.reconnect({ kinds: ["retry"] })
          },
        })
      })
      try {
        await loading
        if (!destroyed) retry.fail(code)
      } catch {
        loading = null
      }
    },
  }
}
