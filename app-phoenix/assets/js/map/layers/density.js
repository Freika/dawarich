import { createRequestScope } from "../data/request_scope.js"
import { FogLayer } from "./fog.js"
import { FogHexagonSource } from "./fog_hexagon_source.js"
import { HexagonLayer } from "./hexagon.js"
import { ScratchLayer } from "./scratch.js"

export function createDensityLayers({
  map,
  reader,
  library,
  loadH3,
  loadProtocol,
  pointsLayer,
  onError,
  onProgress,
  formatCount,
  timers = globalThis,
}) {
  const operations = createRequestScope(timers)
  let current = {}
  let fog, hexagons, scratch, scratchRestoring
  let fogKey, hexagonKey, scratchKey
  let destroyed = false
  const key = (config) =>
    JSON.stringify([
      config.range,
      config.epoch,
      config.fogMode,
      config.fogRadius,
    ])
  const range = () => current.range
  function restore() {
    if (destroyed) return
    if (hexagons && !map.getSource(hexagons.sourceId))
      hexagons.add(hexagons.source.data)
    if (scratch && !map.getSource(scratch.sourceId) && !scratchRestoring) {
      const promise = scratch
        .add()
        .catch((error) => {
          if (error.name !== "AbortError" && !destroyed)
            onError?.("scratch_load_failed")
        })
        .finally(() => {
          if (scratchRestoring === promise) scratchRestoring = null
        })
      scratchRestoring = promise
    }
  }
  map.on("style.load", restore)

  async function update(config, { signal } = {}) {
    operations.reset()
    const operation = operations.begin(signal)
    current = config
    const desired = key(config)
    try {
      if (!config.fogEnabled) {
        fog?.remove()
        fog = null
        fogKey = null
      } else if (fogKey !== desired || !fog) {
        fog?.remove()
        fog = new FogLayer(map, {
          visible: true,
          tiledSource: config.fogMode !== "hexagons",
          mode: config.fogMode,
          clearRadius: config.fogRadius,
          reader,
          getRange: range,
          timers,
          document: map.getContainer().ownerDocument,
          hexSource: new FogHexagonSource({ loadLibrary: loadH3, timers }),
          onError,
        })
        fog.add({ type: "FeatureCollection", features: [] })
        if (config.fogMode === "hexagons")
          await operation.wait(fog._ensureHexagons())
        operation.check()
        fogKey = desired
      }
      pointsLayer?.setSourceKeepAlive(
        config.fogEnabled && config.fogMode !== "hexagons",
      )
      if (!config.hexagonsEnabled) {
        hexagons?.remove()
        hexagons = null
        hexagonKey = null
      } else {
        if (!hexagons) {
          hexagons = new HexagonLayer(map, {
            library,
            reader,
            loadH3,
            timers,
            formatCount,
            onProgress,
            onError,
          })
          hexagons.add()
        }
        if (hexagonKey !== desired) {
          await operation.wait(
            hexagons.load(
              {
                start_at: config.range.startAt,
                end_at: config.range.endAt,
                import_id: config.range.importId,
              },
              { signal: operation.signal },
            ),
          )
          operation.check()
          hexagonKey = desired
        }
      }
      if (!config.scratchEnabled) {
        scratch?.destroy()
        scratch = null
        scratchKey = null
      } else {
        if (!scratch)
          scratch = new ScratchLayer(map, {
            reader,
            getRange: range,
            loadProtocol,
            onTileError: onError,
            onMembershipError: onError,
          })
        if (scratchKey !== desired) {
          if (!map.getSource(scratch.sourceId))
            await operation.wait(
              scratch.add(undefined, undefined, { signal: operation.signal }),
            )
          else
            await operation.wait(scratch.update({ signal: operation.signal }))
          operation.check()
          scratchKey = desired
        }
      }
      operation.check()
    } finally {
      operation.close()
    }
  }

  return {
    update,
    retry(code) {
      if (!scratch || destroyed) return
      return code === "scratch_tiles_failed" ? scratch.refresh() : scratch.update()
    },
    destroy() {
      if (destroyed) return
      destroyed = true
      operations.destroy()
      map.off("style.load", restore)
      fog?.remove()
      hexagons?.remove()
      scratch?.destroy()
      fog = null
      hexagons = null
      scratch = null
      pointsLayer?.setSourceKeepAlive(false)
    },
  }
}
