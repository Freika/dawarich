export function handleAreaCreated(areasLayer, layer, apiKey) {
  const radius = layer.getRadius();
  const center = layer.getLatLng();

  const formHtml = `
    <div class="card w-96 max-w-sm bg-content-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">New Area</h2>
        <form id="circle-form">
          <div class="form-control">
            <label for="circle-name" class="label">
              <span class="label-text">Name</span>
            </label>
            <input type="text" id="circle-name" name="area[name]" class="input input-bordered input-ghost focus:input-ghost w-full max-w-xs" required>
          </div>
          <input type="hidden" name="area[latitude]" value="${center.lat}">
          <input type="hidden" name="area[longitude]" value="${center.lng}">
          <input type="hidden" name="area[radius]" value="${radius}">
          <div class="card-actions justify-end mt-4">
            <button type="submit" class="btn btn-primary">Save</button>
          </div>
        </form>
      </div>
    </div>
  `;

  layer.bindPopup(
    formHtml, {
      maxWidth: "auto",
      minWidth: 300
    }
    ).openPopup();

  layer.on('popupopen', () => {
    const form = document.getElementById('circle-form');

    if (!form) return;

    form.addEventListener('submit', (e) => {
      e.preventDefault();
      saveArea(new FormData(form), areasLayer, layer, apiKey);
    });
  });

  // Add the layer to the areas layer group
  areasLayer.addLayer(layer);
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
      Name: ${data.name}<br>
      Radius: ${Math.round(data.radius)} meters<br>
      <a href="#" data-id="${data.id}" class="delete-area">[Delete]</a>
    `).openPopup();

    // Add event listener for the delete button
    layer.on('popupopen', () => {
      document.querySelector('.delete-area').addEventListener('click', () => {
        deleteArea(data.id, areasLayer, layer, apiKey);
      });
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
  })
  .catch(error => {
    console.error('There was a problem with the delete request:', error);
  });
}

export function fetchAndDrawAreas(areasLayer, apiKey) {
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
    data.forEach(area => {
      // Check if necessary fields are present
      if (area.latitude && area.longitude && area.radius && area.name && area.id) {
        const layer = L.circle([area.latitude, area.longitude], {
          radius: area.radius,
          color: 'red',
          fillColor: '#f03',
          fillOpacity: 0.5
        }).bindPopup(`
          Name: ${area.name}<br>
          Radius: ${Math.round(area.radius)} meters<br>
          <a href="#" data-id="${area.id}" class="delete-area">[Delete]</a>
        `);

        areasLayer.addLayer(layer); // Add to areas layer group

        // Add event listener for the delete button
        layer.on('popupopen', () => {
          document.querySelector('.delete-area').addEventListener('click', (e) => {
            e.preventDefault();
            if (confirm('Are you sure you want to delete this area?')) {
              deleteArea(area.id, areasLayer, layer, apiKey);
            }
          });
        });
      } else {
        console.error('Area missing required fields:', area);
      }
    });
  })
  .catch(error => {
    console.error('There was a problem with the fetch request:', error);
  });
}
