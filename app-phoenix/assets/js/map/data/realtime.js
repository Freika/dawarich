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
  const pending = new Set()
  const refresh = createRefresh({
      ...options,
      run: () => {
        const batch = { kinds: [...pending] }
        pending.clear()
        return options.run(batch)
      },
    }),
    seen = new Map()
  return {
    invalidate(receipt = {}) {
      if (!kinds.has(receipt.kind ?? "map")) return Promise.resolve("ignored")
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
      pending.add(receipt.kind ?? "map")
      return refresh.schedule()
    },
    reconnect: () => {
      pending.add("reconnect")
      return refresh.schedule()
    },
    destroy: () => {
      pending.clear()
      refresh.destroy()
    },
  }
}
