export function createTileFreshness(
  origin = globalThis.location?.origin ?? "http://localhost",
) {
  const scope = globalThis.crypto.randomUUID()
  const versions = new Map()
  const paths = new Map([
    ["points", "/native/map/data/tiles/points/"],
    ["tracks", "/native/map/data/tiles/tracks/"],
  ])
  return {
    bump(kind) {
      if (!paths.has(kind)) throw new TypeError("Unknown tile source")
      versions.set(kind, (versions.get(kind) ?? 0) + 1)
    },
    transformRequest(input) {
      const url = new URL(input, origin)
      const kind = [...paths].find(([, path]) =>
        url.pathname.startsWith(path),
      )?.[0]
      if (url.origin !== origin || !kind || url.username || url.password) {
        return { url: input, credentials: "omit" }
      }
      if (versions.has(kind))
        url.searchParams.set("_", `${scope}-${versions.get(kind)}`)
      return { url: url.href, credentials: "same-origin" }
    },
    destroy() {
      versions.clear()
    },
  }
}
