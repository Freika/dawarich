import { timeOverlapOpacityExpr } from "../algorithms/time_overlap.js";
import { createRequestScope } from "../data/request_scope.js";
import { panelPadding } from "./padding.js";

export function createHostVisits({
  map,
  root,
  reader,
  lifetime,
  getConfig,
  entities,
  blocked = () => false,
}) {
  const requests = createRequestScope();
  const paints = new Map();
  let selectedId = null;
  let revision = getConfig().revision;
  let pointing = false;
  let destroyed = false;
  function presentation() {
    entities()?.visitPresentation({ selectedId });
  }
  function clear() {
    requests.reset();
    selectedId = null;
    presentation();
  }
  async function select(payload) {
    if (destroyed) return;
    clear();
    const id = Number(payload.id);
    if (!Number.isSafeInteger(id) || id <= 0) return;
    const operation = requests.begin();
    const range = getConfig().range;
    try {
      const rows = await operation.wait(
        reader.pages(
          "visits",
          {
            start_at: range.startAt,
            end_at: range.endAt,
          },
          { signal: operation.signal },
        ),
      );
      operation.check();
      const visit = rows.find((row) => Number(row.id) === id);
      if (!visit) return;
      const center = [
        Number(visit.place?.longitude),
        Number(visit.place?.latitude),
      ];
      if (
        !center.every(Number.isFinite) ||
        Math.abs(center[0]) > 180 ||
        Math.abs(center[1]) > 90
      )
        return;
      selectedId = id;
      presentation();
      map.flyTo({
        center,
        zoom: Math.max(map.getZoom(), 15),
        duration: 600,
        padding: panelPadding({
          container: map.getContainer(),
          overlay: () => root?.querySelector(".map-button-cluster"),
        })(),
      });
      root
        ?.querySelector(`#native-visit-${id}`)
        ?.scrollIntoView?.({ block: "nearest" });
    } catch {
    } finally {
      operation.close();
    }
  }
  function paint(id, name, value, fallback) {
    if (!map.getLayer(id)) return;
    const key = `${id}:${name}`;
    if (!paints.has(key))
      paints.set(key, {
        id,
        name,
        value: map.getPaintProperty?.(id, name) ?? fallback,
      });
    map.setPaintProperty(id, name, value);
  }
  function leave() {
    entities()?.visitLabelOpacity?.(null);
    for (const { id, name, value } of paints.values())
      if (map.getLayer(id)) map.setPaintProperty(id, name, value);
    paints.clear();
  }
  function enter(event) {
    const row = event.target.closest?.("[data-entry]");
    if (!row || !["visit", "journey"].includes(row.dataset.entry)) return;
    leave();
    const start = Date.parse(row.dataset.startedAt) / 1000;
    const end = Date.parse(row.dataset.endedAt) / 1000;
    if (!Number.isFinite(start) || !Number.isFinite(end)) return;
    const visit = row.dataset.entry === "visit";
    const id = Number(row.dataset.visitId);
    const opacity = visit ? ["case", ["==", ["get", "id"], id], 1, 0.15] : 0.05;
    paint("visits", "circle-opacity", opacity, 0.9);
    paint("visits", "circle-stroke-opacity", opacity, 1);
    paint("visits-labels", "text-opacity", opacity, 1);
    entities()?.visitLabelOpacity?.(
      visit
        ? (properties) => (Number(properties.id) === id ? 1 : 0.15)
        : () => 0.05,
    );
    paint(
      "tracks-mvt",
      "line-opacity",
      timeOverlapOpacityExpr(
        "start_timestamp",
        "end_timestamp",
        start,
        end,
        1,
        0.08,
      ),
      1,
    );
    for (const name of ["circle-opacity", "circle-stroke-opacity"])
      paint(
        "points-mvt",
        name,
        timeOverlapOpacityExpr(
          "timestamp",
          "max_timestamp",
          start,
          end,
          1,
          0.08,
        ),
        1,
      );
  }
  function move(event) {
    if (blocked()) return;
    const hits = map.getLayer("visits")
      ? map.queryRenderedFeatures?.(event.point, { layers: ["visits"] }) || []
      : [];
    if (hits.length) {
      pointing = true;
      map.getCanvas().style.cursor = "pointer";
    } else if (pointing) {
      pointing = false;
      map.getCanvas().style.cursor = "";
    }
  }
  map.on("mousemove", move);
  root?.addEventListener("pointerover", enter);
  root?.addEventListener("pointerout", leave);
  lifetime.own(() => {
    destroyed = true;
    leave();
    clear();
    requests.destroy();
    map.off("mousemove", move);
    root?.removeEventListener("pointerover", enter);
    root?.removeEventListener("pointerout", leave);
  });
  return {
    select,
    config(config) {
      leave();
      if (config.revision !== revision || !config.visitsEnabled) clear();
      revision = config.revision;
    },
  };
}
