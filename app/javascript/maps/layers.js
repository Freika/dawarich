// Import the maps configuration
// In non-self-hosted mode, we need to mount external maps_config.js to the container
import { mapsConfig as vectorMapsConfig } from './vector_maps_config';
import { mapsConfig as rasterMapsConfig } from './raster_maps_config';

export function createMapLayer(map, selectedLayerName, layerKey, selfHosted) {
  const config = selfHosted === "true" ? rasterMapsConfig[layerKey] : vectorMapsConfig[layerKey];

  if (!config) {
    console.warn(`No configuration found for layer: ${layerKey}`);
    return null;
  }

  let layer;

  if (selfHosted === "true") {
    layer = L.tileLayer(config.url, {
      maxZoom: config.maxZoom,
      attribution: config.attribution,
      crossOrigin: true,
      // Add any other config properties that might be needed
    });
  } else {
    // Use the global protomapsL object (loaded via script tag)
    try {
      if (typeof window.protomapsL === 'undefined') {
        throw new Error('protomapsL is not defined');
      }

      layer = window.protomapsL.leafletLayer({
        url: config.url,
        flavor: config.flavor,
        crossOrigin: true,
      });
    } catch (error) {
      console.error('Error creating protomaps layer:', error);
      throw new Error('Failed to create vector tile layer. protomapsL may not be available.');
    }
  }

  if (selectedLayerName === layerKey) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}

// Helper function to create all map layers
export function createAllMapLayers(map, selectedLayerName, selfHosted) {
  const layers = {};
  const mapsConfig = selfHosted === "true" ? rasterMapsConfig : vectorMapsConfig;
  Object.keys(mapsConfig).forEach(layerKey => {
    layers[layerKey] = createMapLayer(map, selectedLayerName, layerKey, selfHosted);
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
