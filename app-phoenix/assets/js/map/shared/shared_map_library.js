export async function loadSharedMap({ signal }) {
  const [maplibre, styles] = await Promise.all([
    import("/maplibre/6.4.1/maplibre-gl.mjs"),
    import("../../demo/map_style.js"),
  ])
  const style = await styles.demoStyle(undefined, (url) =>
    fetch(url, { signal }),
  )
  if (!document.getElementById("native-maplibre-css")) {
    const css = document.createElement("link")
    css.id = "native-maplibre-css"
    css.rel = "stylesheet"
    css.href = "/maplibre/6.4.1/maplibre-gl.css"
    document.head.append(css)
  }
  return { maplibre, style }
}
