export function createPlaceLabels({ map, library, layerId, kind = "places" }) {
  const markers = new Map();
  let visible = true;
  let opacity = () => 1;
  const document = map.getContainer().ownerDocument;
  const clear = () => {
    for (const marker of markers.values()) marker.remove();
    markers.clear();
  };
  function refresh() {
    if (
      !visible ||
      !map.getLayer(layerId) ||
      map.getLayoutProperty?.(layerId, "visibility") === "none"
    )
      return clear();
    let rows;
    try {
      rows = map.queryRenderedFeatures(undefined, { layers: [layerId] });
    } catch {
      return;
    }
    const admitted = new Set();
    for (const row of rows) {
      const id = String(row.properties.id);
      const coordinates =
        row.geometry?.type === "Point"
          ? row.geometry.coordinates
          : [Number(row.properties.longitude), Number(row.properties.latitude)];
      if (!coordinates?.every(Number.isFinite)) continue;
      admitted.add(id);
      let marker = markers.get(id);
      if (!marker) {
        const element = document.createElement("span");
        element.className = `map-html-label--${kind}`;
        Object.assign(element.style, {
          pointerEvents: "none",
          fontSize: "11px",
          color: "#111827",
          textShadow: "0 0 2px white, 0 0 2px white",
          overflowWrap: "anywhere",
          maxWidth: "180px",
        });
        marker = new library.Marker({ element, anchor: "top", offset: [0, 14] })
          .setLngLat(coordinates)
          .addTo(map);
        markers.set(id, marker);
      }
      marker.getElement().textContent = row.properties.name ?? "";
      marker.setLngLat(coordinates);
      marker.getElement().style.opacity = String(opacity(row.properties));
    }
    for (const [id, marker] of markers)
      if (!admitted.has(id)) {
        marker.remove();
        markers.delete(id);
      }
  }
  map.on("render", refresh);
  return {
    refresh,
    opacity(next) {
      opacity = next ?? (() => 1);
      refresh();
    },
    visibility(next) {
      visible = next;
      refresh();
    },
    destroy() {
      map.off("render", refresh);
      clear();
    },
  };
}
