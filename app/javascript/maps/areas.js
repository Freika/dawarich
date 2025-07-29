import { showFlashMessage } from "./helpers";

// Add custom CSS for popup styling
const addPopupStyles = () => {
  if (!document.querySelector('#area-popup-styles')) {
    const style = document.createElement('style');
    style.id = 'area-popup-styles';
        style.textContent = `
      .area-form-popup,
      .area-info-popup {
        background: transparent !important;
      }

      .area-form-popup .leaflet-popup-content-wrapper,
      .area-info-popup .leaflet-popup-content-wrapper {
        background: transparent !important;
        padding: 0 !important;
        margin: 0 !important;
        border-radius: 0 !important;
        box-shadow: none !important;
        border: none !important;
      }

      .area-form-popup .leaflet-popup-content,
      .area-info-popup .leaflet-popup-content {
        margin: 0 !important;
        padding: 0 1rem 0 0 !important;
        background: transparent !important;
        border-radius: 1rem !important;
        overflow: hidden !important;
        width: 100% !important;
        max-width: none !important;
      }

      .area-form-popup .leaflet-popup-tip,
      .area-info-popup .leaflet-popup-tip {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
      }

      .area-form-popup .leaflet-popup,
      .area-info-popup .leaflet-popup {
        margin-bottom: 0 !important;
      }

      .area-form-popup .leaflet-popup-close-button,
      .area-info-popup .leaflet-popup-close-button {
        right: 1.25rem !important;
        top: 1.25rem !important;
        width: 1.5rem !important;
        height: 1.5rem !important;
        padding: 0 !important;
        color: oklch(var(--bc) / 0.6) !important;
        background: oklch(var(--b2)) !important;
        border-radius: 0.5rem !important;
        border: 1px solid oklch(var(--bc) / 0.2) !important;
        font-size: 1rem !important;
        font-weight: bold !important;
        line-height: 1 !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        transition: all 0.2s ease !important;
      }

      .area-form-popup .leaflet-popup-close-button:hover,
      .area-info-popup .leaflet-popup-close-button:hover {
        background: oklch(var(--b3)) !important;
        color: oklch(var(--bc)) !important;
        border-color: oklch(var(--bc) / 0.3) !important;
      }
    `;
    document.head.appendChild(style);
  }
};

export function handleAreaCreated(areasLayer, layer, apiKey) {
  // Add popup styles
  addPopupStyles();
  const radius = layer.getRadius();
  const center = layer.getLatLng();

  // Configure the layer with the same settings as existing areas
  layer.setStyle({
    color: 'red',
    fillColor: '#f03',
    fillOpacity: 0.5,
    weight: 2,
    interactive: true,
    bubblingMouseEvents: false
  });
  
  // Set the pane to match existing areas
  layer.options.pane = 'areasPane';

  const formHtml = `
    <div class="card w-96 bg-base-100 border border-base-300 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-gray-500">New Area</h2>
        <form id="circle-form" class="space-y-4">
          <div class="form-control">
            <input type="text"
                   id="circle-name"
                   name="area[name]"
                   class="input input-bordered input-primary w-full bg-base-200 text-base-content placeholder-base-content/70 border-base-300 focus:border-primary focus:bg-base-100"
                   placeholder="Enter area name"
                   autofocus
                   required>
          </div>
          <input type="hidden" name="area[latitude]" value="${center.lat}">
          <input type="hidden" name="area[longitude]" value="${center.lng}">
          <input type="hidden" name="area[radius]" value="${radius}">
          <div class="flex justify-between mt-4">
            <button type="button"
                    class="btn btn-outline btn-neutral text-base-content border-base-300 hover:bg-base-200"
                    onclick="this.closest('.leaflet-popup').querySelector('.leaflet-popup-close-button').click()">
              Cancel
            </button>
            <button type="button" id="save-area-btn" class="btn btn-primary">Save Area</button>
          </div>
        </form>
      </div>
    </div>
  `;

  layer.bindPopup(formHtml, {
    maxWidth: 400,
    minWidth: 384,
    maxHeight: 600,
    closeButton: true,
    closeOnClick: false,
    className: 'area-form-popup',
    autoPan: true,
    keepInView: true
  }).openPopup();

  areasLayer.addLayer(layer);

  // Bind the event handler immediately after opening the popup
  setTimeout(() => {
    const form = document.getElementById('circle-form');
    const saveButton = document.getElementById('save-area-btn');
    const nameInput = document.getElementById('circle-name');

    if (!form || !saveButton || !nameInput) {
      console.error('Required elements not found');
      return;
    }

    // Focus the name input
    nameInput.focus();

    // Remove any existing click handlers
    const newSaveButton = saveButton.cloneNode(true);
    saveButton.parentNode.replaceChild(newSaveButton, saveButton);

    // Add click handler
    newSaveButton.addEventListener('click', (e) => {
      console.log('Save button clicked');
      e.preventDefault();
      e.stopPropagation();

      if (!nameInput.value.trim()) {
        nameInput.classList.add('input-error', 'border-error');
        return;
      }

      const formData = new FormData(form);

      saveArea(formData, areasLayer, layer, apiKey);
    });
  }, 100); // Small delay to ensure DOM is ready
}

export function saveArea(formData, areasLayer, layer, apiKey) {
  const data = {};
  formData.forEach((value, key) => {
    const keys = key.split('[').map(k => k.replace(']', ''));
    if (keys.length > 1) {
      if (!data[keys[0]]) data[keys[0]] = {};
      data[keys[0]][keys[1]] = value;
    } else {
      data[keys[0]] = value;
    }
  });

  fetch(`/api/v1/areas?api_key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json'},
    body: JSON.stringify(data)
  })
  .then(response => {
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    return response.json();
  })
  .then(data => {
    layer.closePopup();
    layer.bindPopup(`
      <div class="card w-80 bg-base-100 border border-base-300 shadow-lg">
        <div class="card-body">
          <h3 class="card-title text-base-content text-lg">${data.name}</h3>
          <div class="space-y-2 text-base-content/80">
            <p><span class="font-medium text-base-content">Radius:</span> ${Math.round(data.radius)} meters</p>
          </div>
          <div class="card-actions justify-end mt-4">
            <button class="btn btn-sm btn-error delete-area" data-id="${data.id}">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
              Delete
            </button>
          </div>
        </div>
      </div>
    `, {
      maxWidth: 340,
      minWidth: 320,
      className: 'area-info-popup',
      closeButton: true,
      closeOnClick: false
    }).openPopup();

    // Add event listener for the delete button
    layer.on('popupopen', () => {
      const deleteButton = document.querySelector('.delete-area');
      if (deleteButton) {
        deleteButton.addEventListener('click', (e) => {
          e.preventDefault();
          deleteArea(data.id, areasLayer, layer, apiKey);
        });
      }
    });
  })
  .catch(error => {
    console.error('There was a problem with the save request:', error);
  });
}

export function deleteArea(id, areasLayer, layer, apiKey) {
  fetch(`/api/v1/areas/${id}?api_key=${apiKey}`, {
    method: 'DELETE',
    headers: {
      'Content-Type': 'application/json'
    }
  })
  .then(response => {
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    return response.json();
  })
  .then(data => {
    areasLayer.removeLayer(layer); // Remove the layer from the areas layer group

    showFlashMessage('notice', `Area was successfully deleted!`);
  })
  .catch(error => {
    console.error('There was a problem with the delete request:', error);
  });
}

export function fetchAndDrawAreas(areasLayer, apiKey) {
  // Add popup styles
  addPopupStyles();

  fetch(`/api/v1/areas?api_key=${apiKey}`, {
    method: 'GET',
    headers: {
      'Content-Type': 'application/json'
    }
  })
  .then(response => {
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    return response.json();
  })
  .then(data => {
    // Clear existing areas
    areasLayer.clearLayers();

    data.forEach(area => {
      if (area.latitude && area.longitude && area.radius && area.name && area.id) {
        // Convert string coordinates to numbers
        const lat = parseFloat(area.latitude);
        const lng = parseFloat(area.longitude);
        const radius = parseFloat(area.radius);

        // Create circle with custom pane
        const circle = L.circle([lat, lng], {
          radius: radius,
          color: 'red',
          fillColor: '#f03',
          fillOpacity: 0.5,
          weight: 2,
          interactive: true,
          bubblingMouseEvents: false,
          pane: 'areasPane'
        });

        // Bind popup content with proper theme-aware styling
        const popupContent = `
          <div class="card w-96 bg-base-100 border border-base-300 shadow-xl">
            <div class="card-body">
              <h2 class="card-title text-base-content text-xl">${area.name}</h2>
              <div class="space-y-3">
                <div class="stats stats-vertical shadow bg-base-200">
                  <div class="stat py-2">
                    <div class="stat-title text-base-content/70 text-sm">Radius</div>
                    <div class="stat-value text-base-content text-lg">${Math.round(radius)} meters</div>
                  </div>
                  <div class="stat py-2">
                    <div class="stat-title text-base-content/70 text-sm">Center</div>
                    <div class="stat-value text-base-content text-sm">[${lat.toFixed(4)}, ${lng.toFixed(4)}]</div>
                  </div>
                </div>
              </div>
              <div class="card-actions justify-between items-center mt-6">
                <div class="badge badge-primary badge-outline">Area ${area.id}</div>
                <button class="btn btn-error btn-sm delete-area" data-id="${area.id}">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                  Delete
                </button>
              </div>
            </div>
          </div>
        `;
        circle.bindPopup(popupContent, {
          maxWidth: 400,
          minWidth: 384,
          className: 'area-info-popup',
          closeButton: true,
          closeOnClick: false
        });

        // Add delete button handler when popup opens
        circle.on('popupopen', () => {
          const deleteButton = document.querySelector('.delete-area[data-id="' + area.id + '"]');
          if (deleteButton) {
            deleteButton.addEventListener('click', (e) => {
              e.preventDefault();
              e.stopPropagation();
              if (confirm('Are you sure you want to delete this area?')) {
                deleteArea(area.id, areasLayer, circle, apiKey);
              }
            });
          }
        });

        // Add to layer group
        areasLayer.addLayer(circle);

        // Wait for the circle to be added to the DOM
        setTimeout(() => {
          const circlePath = circle.getElement();
          if (circlePath) {
            // Add CSS styles
            circlePath.style.cursor = 'pointer';
            circlePath.style.transition = 'all 0.3s ease';

            // Add direct DOM event listeners
            circlePath.addEventListener('click', (e) => {
              e.stopPropagation();
              circle.openPopup();
            });

            circlePath.addEventListener('mouseenter', (e) => {
              e.stopPropagation();
              circle.setStyle({
                fillOpacity: 0.8,
                weight: 3
              });
            });

            circlePath.addEventListener('mouseleave', (e) => {
              e.stopPropagation();
              circle.setStyle({
                fillOpacity: 0.5,
                weight: 2
              });
            });
          }
        }, 100);
      }
    });
  })
  .catch(error => {
    console.error('There was a problem with the fetch request:', error);
  });
}
