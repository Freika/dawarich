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

export function osmHotMapLayer(map, selectedLayerName) {
  let layerName = "OpenStreetMap.HOT";
  let layer = L.tileLayer("https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: "© OpenStreetMap contributors, Tiles style by Humanitarian OpenStreetMap Team hosted by OpenStreetMap France",
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}

export function OPNVMapLayer(map, selectedLayerName) {
  let layerName = 'OPNV';
  let layer = L.tileLayer('https://tileserver.memomaps.de/tilegen/{z}/{x}/{y}.png', {
    maxZoom: 18,
    attribution: 'Map <a href="https://memomaps.de/">memomaps.de</a> <a href="http://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}

export function openTopoMapLayer(map, selectedLayerName) {
  let layerName = 'openTopo';
  let layer = L.tileLayer('https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png', {
    maxZoom: 17,
    attribution: 'Map data: &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, <a href="http://viewfinderpanoramas.org">SRTM</a> | Map style: &copy; <a href="https://opentopomap.org">OpenTopoMap</a> (<a href="https://creativecommons.org/licenses/by-sa/3.0/">CC-BY-SA</a>)'
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}

export function cyclOsmMapLayer(map, selectedLayerName) {
  let layerName = 'cyclOsm';
  let layer = L.tileLayer('https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png', {
    maxZoom: 20,
    attribution: '<a href="https://github.com/cyclosm/cyclosm-cartocss-style/releases" title="CyclOSM - Open Bicycle render">CyclOSM</a> | Map data: &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}

export function esriWorldStreetMapLayer(map, selectedLayerName) {
  let layerName = 'esriWorldStreet';
  let layer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}', {
    minZoom: 1,
    maxZoom: 19,
    bounds: [[-90, -180], [90, 180]],
    noWrap: true,
    attribution: 'Tiles &copy; Esri &mdash; Source: Esri, DeLorme, NAVTEQ, USGS, Intermap, iPC, NRCAN, Esri Japan, METI, Esri China (Hong Kong), Esri (Thailand), TomTom, 2012'
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}

export function esriWorldTopoMapLayer(map, selectedLayerName) {
  let layerName = 'esriWorldTopo';
  let layer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}', {
    minZoom: 1,
    maxZoom: 19,
    bounds: [[-90, -180], [90, 180]],
    noWrap: true,
    attribution: 'Tiles &copy; Esri &mdash; Esri, DeLorme, NAVTEQ, TomTom, Intermap, iPC, USGS, FAO, NPS, NRCAN, GeoBase, Kadaster NL, Ordnance Survey, Esri Japan, METI, Esri China (Hong Kong), and the GIS User Community'
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}

export function esriWorldImageryMapLayer(map, selectedLayerName) {
  let layerName = 'esriWorldImagery';
  let layer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
    minZoom: 1,
    maxZoom: 19,
    bounds: [[-90, -180], [90, 180]],
    noWrap: true,
    attribution: 'Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community'
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}

export function esriWorldGrayCanvasMapLayer(map, selectedLayerName) {
  let layerName = 'esriWorldGrayCanvas';
  let layer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}', {
    minZoom: 1,
    maxZoom: 16,
    bounds: [[-90, -180], [90, 180]],
    noWrap: true,
    attribution: 'Tiles &copy; Esri &mdash; Esri, DeLorme, NAVTEQ'
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}
