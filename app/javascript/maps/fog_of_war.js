export function initializeFogCanvas(map) {
  // Remove existing fog canvas if it exists
  const oldFog = document.getElementById('fog');
  if (oldFog) oldFog.remove();

  // Create new fog canvas
  const fog = document.createElement('canvas');
  fog.id = 'fog';
  fog.style.position = 'absolute';
  fog.style.top = '0';
  fog.style.left = '0';
  fog.style.pointerEvents = 'none';
  fog.style.zIndex = '400';

  // Set canvas size to match map container
  const mapSize = map.getSize();
  fog.width = mapSize.x;
  fog.height = mapSize.y;

  // Add canvas to map container
  map.getContainer().appendChild(fog);

  return fog;
}

export function drawFogCanvas(map, markers, clearFogRadius, fogLineThreshold) {
  const fog = document.getElementById('fog');
  // Return early if fog element doesn't exist or isn't a canvas
  if (!fog || !(fog instanceof HTMLCanvasElement)) return;

  const ctx = fog.getContext('2d');
  if (!ctx) return;

  const size = map.getSize();

  // Update canvas size if needed
  if (fog.width !== size.x || fog.height !== size.y) {
    fog.width = size.x;
    fog.height = size.y;
  }
// 1) Paint base fog
  ctx.clearRect(0, 0, size.x, size.y);
  ctx.fillStyle = 'rgba(0, 0, 0, 0.4)';
  ctx.fillRect(0, 0, size.x, size.y);

  // 2) Cut out holes
  ctx.globalCompositeOperation = 'destination-out';

  // 3) Build & sort points
  const pts = markers
    .map(pt => {
      const pixel = map.latLngToContainerPoint(L.latLng(pt[0], pt[1]));
      return { pixel, time: parseInt(pt[4], 10) };
    })
    .sort((a, b) => a.time - b.time);

  const radiusPx = Math.max(metersToPixels(map, clearFogRadius), 2);
  console.log(radiusPx);

  // 4) Mark which pts are part of a line
  const connected = new Array(pts.length).fill(false);
  for (let i = 0; i < pts.length - 1; i++) {
    if (pts[i + 1].time - pts[i].time <= fogLineThreshold) {
      connected[i]     = true;
      connected[i + 1] = true;
    }
  }

  // 5) Draw circles only for “alone” points
  pts.forEach((pt, i) => {
    if (!connected[i]) {
      ctx.fillStyle = 'rgba(255,255,255,1)';
      ctx.beginPath();
      ctx.arc(pt.pixel.x, pt.pixel.y, radiusPx, 0, Math.PI * 2);
      ctx.fill();
    }
  });

  // 6) Draw rounded lines
  ctx.lineWidth = radiusPx * 2;
  ctx.lineCap   = 'round';
  ctx.lineJoin  = 'round';
  ctx.strokeStyle = 'rgba(255,255,255,1)';

  for (let i = 0; i < pts.length - 1; i++) {
    if (pts[i + 1].time - pts[i].time <= fogLineThreshold) {
      ctx.beginPath();
      ctx.moveTo(pts[i].pixel.x, pts[i].pixel.y);
      ctx.lineTo(pts[i + 1].pixel.x, pts[i + 1].pixel.y);
      ctx.stroke();
    }
  }

  // 7) Reset composite operation
  ctx.globalCompositeOperation = 'source-over';
}

function metersToPixels(map, meters) {
  const zoom = map.getZoom();
  const latLng = map.getCenter();
  const metersPerPixel = getMetersPerPixel(latLng.lat, zoom);
  return meters / metersPerPixel;
}

function getMetersPerPixel(latitude, zoom) {
  const earthCircumference = 40075016.686;
  return earthCircumference * Math.cos(latitude * Math.PI / 180) / Math.pow(2, zoom + 8);
}

export function createFogOverlay() {
  return L.Layer.extend({
    onAdd: function(map) {
      this._map = map;
      
      // Initialize storage for fog parameters
      this._markers = [];
      this._clearFogRadius = 50;
      this._fogLineThreshold = 90;

      // Initialize the fog canvas
      initializeFogCanvas(map);

      // Fog overlay will be initialized via updateFog() call from maps controller
      // No need to try to access controller data here

      // Add resize event handlers to update fog size
      this._onResize = () => {
        const fog = document.getElementById('fog');
        if (fog) {
          const mapSize = map.getSize();
          fog.width = mapSize.x;
          fog.height = mapSize.y;

          // Redraw fog after resize
          if (this._controller && this._controller.markers) {
            drawFogCanvas(map, this._controller.markers, this._controller.clearFogRadius, this._controller.fogLineThreshold);
          }
        }
      };

      // Add event handlers for zoom and pan to update fog position
      this._onMoveEnd = () => {
        console.log('Fog: moveend event fired');
        if (this._markers && this._markers.length > 0) {
          console.log('Fog: redrawing after move with stored data');
          drawFogCanvas(map, this._markers, this._clearFogRadius, this._fogLineThreshold);
        } else {
          console.log('Fog: no stored markers available');
        }
      };

      this._onZoomEnd = () => {
        console.log('Fog: zoomend event fired');
        if (this._markers && this._markers.length > 0) {
          console.log('Fog: redrawing after zoom with stored data');
          drawFogCanvas(map, this._markers, this._clearFogRadius, this._fogLineThreshold);
        } else {
          console.log('Fog: no stored markers available');
        }
      };

      // Bind event listeners
      map.on('resize', this._onResize);
      map.on('moveend', this._onMoveEnd);
      map.on('zoomend', this._onZoomEnd);
    },

    onRemove: function(map) {
      const fog = document.getElementById('fog');
      if (fog) {
        fog.remove();
      }

      // Clean up event listeners
      if (this._onResize) {
        map.off('resize', this._onResize);
      }
      if (this._onMoveEnd) {
        map.off('moveend', this._onMoveEnd);
      }
      if (this._onZoomEnd) {
        map.off('zoomend', this._onZoomEnd);
      }
    },

    // Method to update fog when markers change
    updateFog: function(markers, clearFogRadius, fogLineThreshold) {
      if (this._map) {
        // Store the updated parameters
        this._markers = markers || [];
        this._clearFogRadius = clearFogRadius || 50;
        this._fogLineThreshold = fogLineThreshold || 90;
        
        console.log('Fog: updateFog called with', markers?.length || 0, 'markers');
        drawFogCanvas(this._map, this._markers, this._clearFogRadius, this._fogLineThreshold);
      }
    }
  });
}
