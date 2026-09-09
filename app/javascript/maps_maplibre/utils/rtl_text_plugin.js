export function registerRTLTextPlugin(maplibregl, pluginURL) {
  const status = maplibregl.getRTLTextPluginStatus()
  if (status !== "unavailable" && status !== "requested") return

  return maplibregl.setRTLTextPlugin(pluginURL, true).catch((error) => {
    console.warn("[MapLibre] RTL text plugin failed to load:", error)
  })
}
