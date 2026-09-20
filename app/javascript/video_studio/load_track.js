// Pulls the studio's two inputs off a provider, points first.
//
// Order matters: points() resolves the explicit exact-data load used only by
// the studio; ordinary map browsing remains tile-only.
export async function loadTrack(provider) {
  const points = await provider.points()
  return { trackGeojson: provider.trackGeojson(), points }
}
