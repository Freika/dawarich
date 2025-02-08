import { showFlashMessage } from "./helpers";

export function handleAreaCreated(areasLayer, layer, apiKey) {
  console.log('handleAreaCreated called with apiKey:', apiKey);
  const radius = layer.getRadius();
  const center = layer.getLatLng();

  const formHtml = `
    <div class="card w-96">
      <div class="card-body">
        <h2 class="card-title">New Area</h2>
        <form id="circle-form" class="space-y-4">
          <div class="form-control">
            <input type="text"
                   id="circle-name"
                   name="area[name]"
                   class="input input-bordered w-full"
                   placeholder="Enter area name"
                   autofocus
                   required>
          </div>
          <input type="hidden" name="area[latitude]" value="${center.lat}">
          <input type="hidden" name="area[longitude]" value="${center.lng}">
          <input type="hidden" name="area[radius]" value="${radius}">
          <div class="flex justify-between mt-4">
            <button type="button"
                    class="btn btn-outline"
                    onclick="this.closest('.leaflet-popup').querySelector('.leaflet-popup-close-button').click()">
              Cancel
            </button>
            <button type="button" id="save-area-btn" class="btn btn-primary">Save Area</button>
          </div>
        </form>
      </div>
    </div>
  `;

  console.log('Binding popup to layer');
  layer.bindPopup(formHtml, {
    maxWidth: "auto",
    minWidth: 300,
    closeButton: true,
    closeOnClick: false,
    className: 'area-form-popup'
  }).openPopup();

  console.log('Adding layer to areasLayer');
  areasLayer.addLayer(layer);

  // Bind the event handler immediately after opening the popup
  setTimeout(() => {
    console.log('Setting up form handlers');
    const form = document.getElementById('circle-form');
    const saveButton = document.getElementById('save-area-btn');
    const nameInput = document.getElementById('circle-name');

    console.log('Form:', form);
    console.log('Save button:', saveButton);
    console.log('Name input:', nameInput);

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
        console.log('Name is empty');
        nameInput.classList.add('input-error');
        return;
      }

      console.log('Creating FormData');
      const formData = new FormData(form);
      formData.forEach((value, key) => {
        console.log(`FormData: ${key} = ${value}`);
      });

      console.log('Calling saveArea');
      saveArea(formData, areasLayer, layer, apiKey);
    });
  }, 100); // Small delay to ensure DOM is ready
}

export function saveArea(formData, areasLayer, layer, apiKey) {
  console.log('saveArea called with apiKey:', apiKey);
  const data = {};
  formData.forEach((value, key) => {
    console.log('FormData entry:', key, value);
    const keys = key.split('[').map(k => k.replace(']', ''));
    if (keys.length > 1) {
      if (!data[keys[0]]) data[keys[0]] = {};
      data[keys[0]][keys[1]] = value;
    } else {
      data[keys[0]] = value;
    }
  });

  console.log('Sending fetch request with data:', data);
  fetch(`/api/v1/areas?api_key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json'},
    body: JSON.stringify(data)
  })
  .then(response => {
    console.log('Received response:', response);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    return response.json();
  })
  .then(data => {
    console.log('Area saved successfully:', data);
    layer.closePopup();
    layer.bindPopup(`
      Name: ${data.name}<br>
      Radius: ${Math.round(data.radius)} meters<br>
      <a href="#" data-id="${data.id}" class="delete-area">[Delete]</a>
    `).openPopup();

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
  console.log('Fetching areas...');
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

        // Bind popup content
        const popupContent = `
          <div class="card w-full">
            <div class="card-body">
              <h2 class="card-title">${area.name}</h2>
              <p>Radius: ${Math.round(radius)} meters</p>
              <p>Center: [${lat.toFixed(4)}, ${lng.toFixed(4)}]</p>
              <div class="flex justify-end mt-4">
                <button class="btn btn-sm btn-error delete-area" data-id="${area.id}">Delete</button>
              </div>
            </div>
          </div>
        `;
        circle.bindPopup(popupContent);

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
