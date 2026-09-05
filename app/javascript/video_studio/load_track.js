// Pulls the studio's two inputs off a provider, points first.
//
// Order matters: MapPageProvider.points() awaits ensurePointsLoaded(), and
// that call is what builds the routes GeoJSON and pushes it into the routes
// layer. Under tiled rendering nothing else ever fills that layer — the bulk
// points and tracks fetches are both skipped — so reading the track first
// yields an empty collection and the studio renders a bare map.
export async function loadTrack(provider) {
  const points = await provider.points()
  return { trackGeojson: provider.trackGeojson(), points }
}
