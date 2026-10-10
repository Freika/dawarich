import { createRefresh } from "./refresh.js"

const kinds = new Set([
  "map",
  "points",
  "tracks",
  "imports",
  "map_edits",
  "family",
  "public",
  "trip",
  "progress",
  "reconnect",
])
export function createRealtime(options) {
  const refresh = createRefresh(options),
    seen = new Map()
  return {
    invalidate(receipt = {}) {
      if (receipt.revision !== undefined) {
        const kind = receipt.kind ?? "map",
          revision = receipt.revision
        if (
          !kinds.has(kind) ||
          !Number.isSafeInteger(revision) ||
          revision < 1 ||
          revision <= (seen.get(kind) ?? 0)
        )
          return Promise.resolve("ignored")
        seen.set(kind, revision)
      }
      return refresh.schedule()
    },
    reconnect: () => refresh.schedule(),
    destroy: () => refresh.destroy(),
  }
}
