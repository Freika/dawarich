// Tiles are HTTP-cached for five minutes. A source reloads in place with its
// URL unchanged (changing the URL blanks the layer until new tiles arrive), so
// map.transformRequest appends a per-refresh version to skip that cache. The
// page-load scope keeps a version from matching one cached by an earlier page.
const PAGE_SCOPE = Math.random().toString(36).slice(2, 10)
const versions = new Map()
let privacyZonesFingerprint = null

// Tiles are masked by the user's privacy zones; the fingerprint keys the
// HTTP cache so an edited zone never serves a tile cut by the old one.
export function setPrivacyZonesFingerprint(fingerprint) {
  const next = fingerprint || null
  if (next === privacyZonesFingerprint) return false
  privacyZonesFingerprint = next
  return true
}

export function bumpTileVersion(pathPrefix) {
  versions.set(pathPrefix, (versions.get(pathPrefix) || 0) + 1)
}

export function withTileVersion(url) {
  if (privacyZonesFingerprint)
    url.searchParams.set("pz", privacyZonesFingerprint)
  for (const [pathPrefix, version] of versions) {
    if (url.pathname.startsWith(pathPrefix))
      url.searchParams.set("_", `${PAGE_SCOPE}-${version}`)
  }
  return url
}
