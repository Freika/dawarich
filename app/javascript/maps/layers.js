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

// Helper function to apply theme-aware layer selection
function getThemeAwareLayerName(preferredLayerName, userTheme, selfHosted) {
  // Only apply theme-aware logic for non-self-hosted (vector) maps
  if (selfHosted === "true") {
    return preferredLayerName;
  }

  // Define light and dark layer groups
  const lightLayers = ["Light", "White", "Grayscale"];
  const darkLayers = ["Dark", "Black"];

  let finalLayerName = preferredLayerName;

  if (userTheme === "light") {
    // If user theme is light and preferred layer is light-compatible, keep it
    if (lightLayers.includes(preferredLayerName)) {
      finalLayerName = preferredLayerName;
    }
    // If user theme is light but preferred layer is dark, default to White
    else if (darkLayers.includes(preferredLayerName)) {
      finalLayerName = "White";
    }
  } else if (userTheme === "dark") {
    // If user theme is dark and preferred layer is dark-compatible, keep it
    if (darkLayers.includes(preferredLayerName)) {
      finalLayerName = preferredLayerName;
    }
    // If user theme is dark but preferred layer is light, default to Dark
    else if (lightLayers.includes(preferredLayerName)) {
      finalLayerName = "Dark";
    }
  }

  return finalLayerName;
}

// Helper function to create all map layers
export function createAllMapLayers(map, selectedLayerName, selfHosted, userTheme = 'dark') {
  const layers = {};
  const mapsConfig = selfHosted === "true" ? rasterMapsConfig : vectorMapsConfig;

  // Apply theme-aware selection
  const themeAwareLayerName = getThemeAwareLayerName(selectedLayerName, userTheme, selfHosted);

  Object.keys(mapsConfig).forEach(layerKey => {
    // Create the layer and add it to the map if it's the theme-aware selected layer
    const layer = createMapLayer(map, themeAwareLayerName, layerKey, selfHosted);
    layers[layerKey] = layer;
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
