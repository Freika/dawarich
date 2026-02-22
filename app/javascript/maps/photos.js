// javascript/maps/photos.js
import L from "leaflet";
import Flash from "controllers/flash_controller";

export async function fetchAndDisplayPhotos({ map, photoMarkers, apiKey, startDate, endDate, userSettings }, retryCount = 0) {
  const MAX_RETRIES = 3;
  const RETRY_DELAY = 3000; // 3 seconds

  console.log('fetchAndDisplayPhotos called with:', {
    startDate,
    endDate,
    retryCount,
    photoMarkersExists: !!photoMarkers,
    mapExists: !!map,
    apiKeyExists: !!apiKey,
    userSettingsExists: !!userSettings
  });

  // Create loading control
  const LoadingControl = L.Control.extend({
    onAdd: (map) => {
      const container = L.DomUtil.create('div', 'leaflet-loading-control');
      container.innerHTML = '<div class="loading-spinner"></div>';
      return container;
    }
  });

  const loadingControl = new LoadingControl({ position: 'topleft' });
  map.addControl(loadingControl);

  try {
    const params = new URLSearchParams({
      api_key: apiKey,
      start_date: startDate,
      end_date: endDate
    });

    console.log('Fetching photos from API:', `/api/v1/photos?${params}`);
    const response = await fetch(`/api/v1/photos?${params}`);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}, response: ${response.body}`);
    }

    const photos = await response.json();
    console.log('Photos API response:', { count: photos.length, photos });
    photoMarkers.clearLayers();

    const photoLoadPromises = photos.map(photo => {
      return new Promise((resolve) => {
        const img = new Image();
        const thumbnailUrl = `/api/v1/photos/${photo.id}/thumbnail.jpg?api_key=${apiKey}&source=${photo.source}`;

        img.onload = () => {
          console.log('Photo thumbnail loaded, creating marker for:', photo.id);
          createPhotoMarker(photo, userSettings, photoMarkers, apiKey);
          resolve();
        };

        img.onerror = () => {
          console.error(`Failed to load photo ${photo.id}`);
          resolve(); // Resolve anyway to not block other photos
        };

        img.src = thumbnailUrl;
      });
    });

    await Promise.all(photoLoadPromises);
    console.log('All photo markers created, adding to map');

    if (!map.hasLayer(photoMarkers)) {
      photoMarkers.addTo(map);
      console.log('Photos layer added to map');
    } else {
      console.log('Photos layer already on map');
    }

    // Show checkmark for 1 second before removing
    const loadingSpinner = document.querySelector('.loading-spinner');
    loadingSpinner.classList.add('done');

    await new Promise(resolve => setTimeout(resolve, 1000));
    console.log('Photos loading completed successfully');

  } catch (error) {
    console.error('Error fetching photos:', error);
    Flash.show('error', 'Failed to fetch photos');

    if (retryCount < MAX_RETRIES) {
      console.log(`Retrying in ${RETRY_DELAY/1000} seconds... (Attempt ${retryCount + 1}/${MAX_RETRIES})`);
      setTimeout(() => {
        fetchAndDisplayPhotos({ map, photoMarkers, apiKey, startDate, endDate, userSettings }, retryCount + 1);
      }, RETRY_DELAY);
    } else {
      Flash.show('error', 'Failed to fetch photos after multiple attempts');
    }
  } finally {
    map.removeControl(loadingControl);
  }
}

function getPhotoLink(photo, userSettings) {
  switch (photo.source) {
    case 'immich':
      const startOfDay = new Date(photo.localDateTime);
      startOfDay.setHours(0, 0, 0, 0);

      const endOfDay = new Date(photo.localDateTime);
      endOfDay.setHours(23, 59, 59, 999);

      const queryParams = {
        takenAfter: startOfDay.toISOString(),
        takenBefore: endOfDay.toISOString()
      };
      const encodedQuery = encodeURIComponent(JSON.stringify(queryParams));

      return `${userSettings.immich_url}/search?query=${encodedQuery}`;
    case 'photoprism':
      return `${userSettings.photoprism_url}/library/browse?view=cards&year=${photo.localDateTime.split('-')[0]}&month=${photo.localDateTime.split('-')[1]}&order=newest&public=true&quality=3`;
    default:
      return '#'; // Default or error case
  }
}

function getSourceUrl(photo, userSettings) {
  switch (photo.source) {
    case 'photoprism':
      return userSettings.photoprism_url;
    case 'immich':
      return userSettings.immich_url;
    default:
      return '#'; // Default or error case
  }
}

export function createPhotoMarker(photo, userSettings, photoMarkers, apiKey) {
  // Handle both data formats - check for exifInfo or direct lat/lng
  const latitude = photo.latitude || photo.exifInfo?.latitude;
  const longitude = photo.longitude || photo.exifInfo?.longitude;

  console.log('Creating photo marker for:', {
    photoId: photo.id,
    latitude,
    longitude,
    hasExifInfo: !!photo.exifInfo,
    hasDirectCoords: !!(photo.latitude && photo.longitude)
  });

  if (!latitude || !longitude) {
    console.warn('Photo missing coordinates, skipping:', photo.id);
    return;
  }

  const thumbnailUrl = `/api/v1/photos/${photo.id}/thumbnail.jpg?api_key=${apiKey}&source=${photo.source}`;

  const icon = L.divIcon({
    className: 'photo-marker',
    html: `<img src="${thumbnailUrl}" style="width: 48px; height: 48px;">`,
    iconSize: [48, 48]
  });

  const marker = L.marker(
    [latitude, longitude],
    { icon }
  );

  const photo_link = getPhotoLink(photo, userSettings);
  const source_url = getSourceUrl(photo, userSettings);

  const popupContent = `
    <div class="max-w-xs">
      <a href="${photo_link}" target="_blank" onmouseover="this.firstElementChild.style.boxShadow = '0 4px 8px rgba(0, 0, 0, 0.3)';"
 onmouseout="this.firstElementChild.style.boxShadow = '';">
        <img src="${thumbnailUrl}"
            class="mb-2 rounded"
            style="transition: box-shadow 0.3s ease;"
            alt="${photo.originalFileName}">
      </a>
      <h3 class="font-bold">${photo.originalFileName}</h3>
      <p>Taken: ${new Date(photo.localDateTime).toLocaleString()}</p>
      <p>Location: ${photo.city}, ${photo.state}, ${photo.country}</p>
      <p>Source: <a href="${source_url}" target="_blank">${photo.source}</a></p>
      ${photo.type === 'VIDEO' ? '🎥 Video' : '📷 Photo'}
    </div>
  `;
  marker.bindPopup(popupContent);

  photoMarkers.addLayer(marker);
  console.log('Photo marker added to layer group');
}
