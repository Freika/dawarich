// Yeah I know it should be DRY but this is me doing a KISS at 21:00 on a Sunday night

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

// export function stadiaAlidadeSmoothMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaAlidadeSmooth';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/alidade_smooth/{z}/{x}/{y}{r}.{ext}', {
//     minZoom: 0,
//     maxZoom: 20,
//     attribution: '&copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'png'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

// export function stadiaAlidadeSmoothDarkMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaAlidadeSmoothDark';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.{ext}', {
//     minZoom: 0,
//     maxZoom: 20,
//     attribution: '&copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'png'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

// export function stadiaAlidadeSatelliteMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaAlidadeSatellite';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/alidade_satellite/{z}/{x}/{y}{r}.{ext}', {
//     minZoom: 0,
//     maxZoom: 20,
//     attribution: '&copy; CNES, Distribution Airbus DS, © Airbus DS, © PlanetObserver (Contains Copernicus Data) | &copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'jpg'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

// export function stadiaOsmBrightMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaOsmBright';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.{ext}', {
//     minZoom: 0,
//     maxZoom: 20,
//     attribution: '&copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'png'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

// export function stadiaOutdoorMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaOutdoor';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/outdoors/{z}/{x}/{y}{r}.{ext}', {
//     minZoom: 0,
//     maxZoom: 20,
//     attribution: '&copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'png'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

// export function stadiaStamenTonerMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaStamenToner';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/stamen_toner/{z}/{x}/{y}{r}.{ext}', {
//     minZoom: 0,
//     maxZoom: 20,
//     attribution: '&copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://www.stamen.com/" target="_blank">Stamen Design</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'png'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

// export function stadiaStamenTonerBackgroundMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaStamenTonerBackground';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/stamen_toner_background/{z}/{x}/{y}{r}.{ext}', {
//     minZoom: 0,
//     maxZoom: 20,
//     attribution: '&copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://www.stamen.com/" target="_blank">Stamen Design</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'png'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

// export function stadiaStamenTonerLiteMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaStamenTonerLite';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/stamen_toner_lite/{z}/{x}/{y}{r}.{ext}', {
//     minZoom: 0,
//     maxZoom: 20,
//     attribution: '&copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://www.stamen.com/" target="_blank">Stamen Design</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'png'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

// export function stadiaStamenWatercolorMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaStamenWatercolor';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/stamen_watercolor/{z}/{x}/{y}.{ext}', {
//     minZoom: 1,
//     maxZoom: 16,
//     attribution: '&copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://www.stamen.com/" target="_blank">Stamen Design</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'jpg'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

// export function stadiaStamenTerrainMapLayer(map, selectedLayerName) {
//   let layerName = 'stadiaStamenTerrain';
//   let layer = L.tileLayer('https://tiles.stadiamaps.com/tiles/stamen_terrain/{z}/{x}/{y}{r}.{ext}', {
//     minZoom: 0,
//     maxZoom: 18,
//     attribution: '&copy; <a href="https://www.stadiamaps.com/" target="_blank">Stadia Maps</a> &copy; <a href="https://www.stamen.com/" target="_blank">Stamen Design</a> &copy; <a href="https://openmaptiles.org/" target="_blank">OpenMapTiles</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     ext: 'png'
//   });

//   if (selectedLayerName === layerName) {
//     return layer.addTo(map);
//   } else {
//     return layer;
//   }
// }

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
    attribution: 'Tiles &copy; Esri &mdash; Esri, DeLorme, NAVTEQ',
    maxZoom: 16
  });

  if (selectedLayerName === layerName) {
    return layer.addTo(map);
  } else {
    return layer;
  }
}
