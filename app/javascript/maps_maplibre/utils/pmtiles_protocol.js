import * as maplibregl from "maplibre-gl"
import { Protocol } from "pmtiles"

let protocolRegistered = false

export function registerPmtilesProtocol() {
  if (protocolRegistered) return
  const protocol = new Protocol()
  maplibregl.addProtocol("pmtiles", protocol.tile)
  protocolRegistered = true
}
