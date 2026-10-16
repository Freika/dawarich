import { createMapRetry } from "../ui/retry.js"
import { mapTranslate } from "../ui/translate.js"

export function installMapRetry({ owner, root, layers, density }) {
  const retry = createMapRetry({
    root,
    translate: mapTranslate(() => owner.config),
    async run(code) {
      if (code === "point_tiles_failed") return layers()?.points.retry()
      if (code === "track_tiles_failed") return layers()?.tracks.retry()
      if (code.startsWith("scratch")) return density()?.retry(code)
      return owner.reconnect({ kinds: ["retry"] })
    },
  })
  const destroy = owner.destroy
  owner.destroy = () => { retry.destroy(); destroy.call(owner) }
  return retry
}
