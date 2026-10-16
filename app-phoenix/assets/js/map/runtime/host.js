import { createReader } from "../data/reader.js";
import { createTileFreshness } from "../data/tile_freshness.js";
import { createHostEditing } from "../edit/host.js";
import { createBaseLayers } from "../layers/tile_layers.js";
import { installHostReplay } from "../replay/host.js";
import { createHostSelection } from "../selection/host.js";
import { fetchStyle } from "../style/load_style.js";
import { createEnrichmentTool } from "../ui/enrichment.js";
import { createHostSearch } from "../ui/host_search.js";
import { createHostSettings } from "../ui/host_settings.js";
import { createHostTimeline } from "../ui/host_timeline.js";
import { createHostTools } from "../ui/host_tools.js";
import { createHostVisits } from "../ui/host_visits.js";
import { createRangeRequests } from "../ui/navigation.js";
import { installStudios } from "../ui/studios.js";
import { createHostAuxLayers } from "./aux_layers.js";
import { createMapRuntime } from "./create_map.js";
import {
  createHostRecentPoint,
  installRecentReconnect,
} from "./recent_point.js";
import { waitForStyle } from "./style_ready.js";
import { createLayerPreferences } from "./layer_preferences.js";
import { installHostSource } from "./studio_source.js";
import { createViewportFit } from "./viewport_fit.js";
export { createMapRuntime };
export function mountHost({
  element,
  pushEvent,
  reader = createReader(),
  loadLibrary = () => import("/maplibre/6.4.1/maplibre-gl.mjs"),
  loadStyle = fetchStyle,
  attach,
  refresh,
}) {
  const fail = (code) => pushEvent("map:failed", { code });
  const requests = createRangeRequests({ pushEvent });
  const freshness = createTileFreshness();
  const fit = createViewportFit(reader, element);
  const root = element.closest?.("[data-native-map-root]");
  const blocked = () =>
    owner.config.editEnabled ||
    owner.selection.state.active ||
    !!root?.querySelector("[data-map-tool-status]")?.textContent?.trim();
  let library;
  let layers;
  let editing;
  let enrichment;
  let timeline;
  let density;
  let aux;
  let entities, recent;
  const initial = JSON.parse(element.dataset.mapConfig ?? "{}");
  const preferences = createLayerPreferences({
    namespace: initial.namespace,
    initial,
    onRestore: (enabled) =>
      pushEvent("map:anomalies", { enabled: String(enabled) }),
  });
  const config = preferences.initial;
  const owner = createMapRuntime({
    element,
    config,
    reader,
    loadLibrary: async (options) => {
      library = await loadLibrary(options);
      return library;
    },
    loadStyle,
    transformRequest: freshness.transformRequest,
    attach:
      attach ??
      (({ map, config, lifetime }) => {
        installStudios({ element, owner, lifetime });
        recent = createHostRecentPoint({ map, reader, lifetime, config });
        installHostReplay({
          onActive: (active) =>
            active ? aux?.photos?.hide() : aux?.photos?.show(),
          library,
          reader,
          owner,
          map,
          lifetime,
          root,
        });
        owner.settings = createHostSettings({
          map,
          loadStyle,
          lifetime,
          getConfig: () => owner.config,
          update: (next) => owner.update(next),
          onError: fail,
        });
        enrichment = createEnrichmentTool({
          map,
          pushEvent,
          reader,
          library,
          root,
        });
        lifetime.own(enrichment.destroy);
        owner.search = createHostSearch({
          map,
          root,
          reader,
          lifetime,
          document: element.ownerDocument,
          pushEvent,
          getConfig: () => owner.config,
        });
        owner.selection = createHostSelection({
          map,
          root,
          reader,
          pushEvent,
          lifetime,
          getConfig: () => owner.config,
        });
        owner.timeline = timeline = createHostTimeline({
          library,
          pushEvent,
          getConfig: () => owner.config,
          replay: () => owner.replay,
          blocked,
          map,
          root,
          reader,
          lifetime,
        });
        owner.visits = createHostVisits({
          map,
          reader,
          lifetime,
          root,
          getConfig: () => owner.config,
          entities: () => entities,
          blocked,
        });
        createHostTools({
          map,
          root,
          pushEvent,
          lifetime,
        });
        layers = createBaseLayers({
          map,
          config,
          freshness,
          onError: fail,
        });
        lifetime.own(() => layers.destroy());
        editing = createHostEditing({
          map,
          reader,
          pushEvent,
          lifetime,
          getConfig: () => owner.config,
          layers,
          document: element.ownerDocument,
          root,
        });
        lifetime.own(() => density?.destroy());
        aux = createHostAuxLayers({
          map,
          reader,
          library,
          root,
          onError: fail,
          replayActive: () => owner.replay?.active,
        });
        lifetime.own(() => aux.destroy());
        lifetime.own(() => entities?.destroy());
        return waitForStyle(map, lifetime).then(() => layers.mount());
      }),
    refresh:
      refresh ??
      (async ({ map, config, operation, signal }) => {
        await fit({ map, config, operation, signal });
        layers?.update(config);
        if (
          !density &&
          (config.fogEnabled || config.hexagonsEnabled || config.scratchEnabled)
        ) {
          const [module, library] = await operation.wait(
            Promise.all([
              import("../layers/density.js"),
              loadLibrary({ signal }),
            ]),
          );
          operation.check();
          density = module.createDensityLayers({
            map,
            reader,
            library,
            pointsLayer: layers?.points,
            onError: fail,
            onProgress: (receipt) =>
              element.dispatchEvent(
                new CustomEvent("map:progress", { detail: receipt }),
              ),
            formatCount: (count) =>
              (owner.config.hexagonLabel ?? "{count} points").replace(
                "{count}",
                new Intl.NumberFormat(owner.config.locale ?? "en").format(
                  count,
                ),
              ),
          });
        }
        if (density) await operation.wait(density.update(config, { signal }));
        if (
          !entities &&
          (config.visitsEnabled ||
            config.placesEnabled ||
            config.areasEnabled ||
            config.anomaliesEnabled)
        ) {
          const [module, library] = await operation.wait(
            Promise.all([
              import("../layers/entities.js"),
              loadLibrary({ signal }),
            ]),
          );
          operation.check();
          entities = module.createEntityLayers({
            map,
            reader,
            library,
            onSelect: (receipt) => {
              if (!blocked()) pushEvent("map:select", receipt);
            },
            onError: fail,
          });
        }
        if (entities) await operation.wait(entities.update(config, { signal }));
        if (aux)
          await operation.wait(aux.update(config, { operation, signal }));
        if (recent) await operation.wait(recent.baseline({ signal }));
      }),
    events: {
      refreshed: (receipt) => pushEvent("map:ready", receipt),
      error: (receipt) => pushEvent("map:failed", receipt),
    },
  });
  Object.defineProperties(owner, {
    enrichment: { get: () => enrichment },
    pointEditing: { get: () => editing?.transport },
    editor: { get: () => editing?.editor },
    entityLayers: { get: () => entities },
    photoLayer: { get: () => aux?.photos },
  });
  owner.visitsFilter = (filter) =>
    owner.update({ ...owner.config, visitFilter: filter });
  owner.layer = ({ layer, enabled }) => {
    if (!["places", "visits", "areas", "anomalies"].includes(layer)) return;
    return owner.update({
      ...owner.config,
      [`${layer}Enabled`]: enabled === true,
    });
  };
  installRecentReconnect(
    owner,
    () => layers,
    () => recent,
    () => editing?.invalidate(),
  );
  const update = owner.update;
  owner.update = (config) => {
    config = preferences.update(config);
    if (config.revision !== owner.config.revision) {
      enrichment?.clear();
      owner.selection?.cancel();
    }
    recent?.config(config);
    aux?.clear(config);
    timeline?.config(config);
    owner.visits?.config(config);
    editing?.config(config);
    const updating = update.call(owner, config);
    requests.config(config);
    return updating;
  };
  requests.config(config);
  installHostSource({
    owner,
    reader,
    requests,
    onDestroy: preferences.destroy,
  });
  return owner;
}
