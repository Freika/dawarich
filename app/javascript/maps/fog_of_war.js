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

export function drawFogCanvas(map, markers, clearFogRadius, fogLinethreshold) {
  const fog = document.getElementById('fog');
  // Return early if fog element doesn't exist or isn't a canvas
  if (!fog || !(fog instanceof HTMLCanvasElement)) return;

  const ctx = fog.getContext('2d');
  if (!ctx) return;

  const size = map.getSize();

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
    if (pts[i + 1].time - pts[i].time <= fogLinethreshold) {
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
    if (pts[i + 1].time - pts[i].time <= fogLinethreshold) {
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
    onAdd: (map) => {
      initializeFogCanvas(map);

      // Add resize event handlers to update fog size
      map.on('resize', () => {
       // Set canvas size to match map container
       const mapSize = map.getSize();
       fog.width = mapSize.x;
       fog.height = mapSize.y;
      });
    },
    onRemove: (map) => {
      const fog = document.getElementById('fog');
      if (fog) {
        fog.remove();
      }
      // Clean up event listener
      map.off('resize');
    }
  });
}
