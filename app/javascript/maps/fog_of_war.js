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

export function drawFogCanvas(map, markers, clearFogRadius) {
  const fog = document.getElementById('fog');
  if (!fog) return;

  const ctx = fog.getContext('2d');
  if (!ctx) return;

  const size = map.getSize();

  // Clear the canvas
  ctx.clearRect(0, 0, size.x, size.y);

  // Keep the light fog for unexplored areas
  ctx.fillStyle = 'rgba(0, 0, 0, 0.4)';
  ctx.fillRect(0, 0, size.x, size.y);

  // Set up for "cutting" holes
  ctx.globalCompositeOperation = 'destination-out';

  // Draw clear circles for each point
  markers.forEach(point => {
    const latLng = L.latLng(point[0], point[1]);
    const pixelPoint = map.latLngToContainerPoint(latLng);
    const radiusInPixels = metersToPixels(map, clearFogRadius);

    // Make explored areas completely transparent
    const gradient = ctx.createRadialGradient(
      pixelPoint.x, pixelPoint.y, 0,
      pixelPoint.x, pixelPoint.y, radiusInPixels
    );
    gradient.addColorStop(0, 'rgba(255, 255, 255, 1)');      // 100% transparent
    gradient.addColorStop(0.85, 'rgba(255, 255, 255, 1)');   // Still 100% transparent
    gradient.addColorStop(1, 'rgba(255, 255, 255, 0)');      // Fade to fog at edge

    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.arc(pixelPoint.x, pixelPoint.y, radiusInPixels, 0, Math.PI * 2);
    ctx.fill();
  });

  // Reset composite operation
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
    },
    onRemove: (map) => {
      const fog = document.getElementById('fog');
      if (fog) {
        fog.remove();
      }
    }
  });
}
