// Import the maps configuration
// In non-self-hosted mode, we need to mount external maps_config.js to the container
import { mapsConfig } from './maps_config';

export function createMapLayer(map, selectedLayerName, layerKey) {
  const config = mapsConfig[layerKey];

  if (!config) {
    console.warn(`No configuration found for layer: ${layerKey}`);
    return null;
  }

  let layer = L.tileLayer(config.url, {
    maxZoom: config.maxZoom,
    attribution: config.attribution,
    // Add any other config properties that might be needed
  });

  if (selectedLayerName === layerKey) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}

// Helper function to create all map layers
export function createAllMapLayers(map, selectedLayerName) {
  const layers = {};

  Object.keys(mapsConfig).forEach(layerKey => {
    layers[layerKey] = createMapLayer(map, selectedLayerName, layerKey);
  });

  return layers;
}

export function osmMapLayer(map, selectedLayerName) {
  let layerName = 'OpenStreetMap';

  let layer = L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: "&copy; <a href='http://www.openstreetmap.org/copyright'>OpenStreetMap</a>",
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}
