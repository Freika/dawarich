/**
 * Example usage of the HexagonGrid implementation
 * This file shows how to use the hexagon grid functionality
 */

import { createHexagonGrid } from './hexagon_grid';

// Example 1: Basic usage with default options
export function basicHexagonExample(map, apiKey) {
  const hexagonGrid = createHexagonGrid(map, {
    apiEndpoint: `/api/v1/maps/hexagons?api_key=${apiKey}`
  });
  
  // Show the grid
  hexagonGrid.show();
  
  return hexagonGrid;
}

// Example 2: Custom styling
export function customStyledHexagonExample(map, apiKey) {
  const hexagonGrid = createHexagonGrid(map, {
    apiEndpoint: `/api/v1/maps/hexagons?api_key=${apiKey}`,
    style: {
      fillColor: '#ff6b6b',
      fillOpacity: 0.2,
      color: '#e74c3c',
      weight: 2,
      opacity: 0.8
    },
    debounceDelay: 500,
    minZoom: 10,
    maxZoom: 18
  });
  
  hexagonGrid.show();
  return hexagonGrid;
}

// Example 3: Interactive hexagons with click handlers
export function interactiveHexagonExample(map, apiKey) {
  const hexagonGrid = createHexagonGrid(map, {
    apiEndpoint: `/api/v1/maps/hexagons?api_key=${apiKey}`,
    style: {
      fillColor: '#4ecdc4',
      fillOpacity: 0.15,
      color: '#26d0ce',
      weight: 1,
      opacity: 0.6
    }
  });
  
  // Override the click handler to add custom behavior
  const originalOnHexagonClick = hexagonGrid.onHexagonClick.bind(hexagonGrid);
  hexagonGrid.onHexagonClick = function(e, feature) {
    // Call original handler
    originalOnHexagonClick(e, feature);
    
    // Add custom behavior
    const hexId = feature.properties.hex_id;
    const center = e.latlng;
    
    // Show a popup with hexagon information
    const popup = L.popup()
      .setLatLng(center)
      .setContent(`
        <div>
          <h4>Hexagon ${hexId}</h4>
          <p>Center: ${center.lat.toFixed(6)}, ${center.lng.toFixed(6)}</p>
          <p>Click to add a marker here</p>
        </div>
      `)
      .openOn(map);
    
    // Add a marker at the hexagon center
    const marker = L.marker(center)
      .addTo(map)
      .bindPopup(`Marker in Hexagon ${hexId}`);
    
    console.log('Hexagon clicked:', {
      id: hexId,
      center: center,
      feature: feature
    });
  };
  
  hexagonGrid.show();
  return hexagonGrid;
}

// Example 4: Dynamic styling based on data
export function dataVisualizationHexagonExample(map, apiKey) {
  const hexagonGrid = createHexagonGrid(map, {
    apiEndpoint: `/api/v1/maps/hexagons?api_key=${apiKey}`,
    style: {
      fillColor: '#3498db',
      fillOpacity: 0.1,
      color: '#2980b9',
      weight: 1,
      opacity: 0.5
    }
  });
  
  // Override the addHexagonsToMap method to add data visualization
  const originalAddHexagons = hexagonGrid.addHexagonsToMap.bind(hexagonGrid);
  hexagonGrid.addHexagonsToMap = function(geojsonData) {
    if (!geojsonData.features || geojsonData.features.length === 0) {
      return;
    }
    
    // Simulate data for each hexagon (in real use, fetch from API)
    const hexagonData = new Map();
    geojsonData.features.forEach(feature => {
      // Simulate point density data
      hexagonData.set(feature.properties.hex_id, Math.random() * 100);
    });
    
    const geoJsonLayer = L.geoJSON(geojsonData, {
      style: (feature) => {
        const density = hexagonData.get(feature.properties.hex_id) || 0;
        const opacity = Math.min(density / 100, 1);
        const color = density > 50 ? '#e74c3c' : density > 25 ? '#f39c12' : '#27ae60';
        
        return {
          fillColor: color,
          fillOpacity: opacity * 0.3,
          color: color,
          weight: 1,
          opacity: opacity * 0.8
        };
      },
      onEachFeature: (feature, layer) => {
        const density = hexagonData.get(feature.properties.hex_id) || 0;
        
        layer.bindPopup(`
          <div>
            <h4>Hexagon ${feature.properties.hex_id}</h4>
            <p>Data Points: ${Math.round(density)}</p>
            <p>Density Level: ${density > 50 ? 'High' : density > 25 ? 'Medium' : 'Low'}</p>
          </div>
        `);
        
        layer.on({
          mouseover: (e) => {
            const layer = e.target;
            layer.setStyle({
              fillOpacity: 0.5,
              weight: 2
            });
          },
          mouseout: (e) => {
            const layer = e.target;
            const density = hexagonData.get(feature.properties.hex_id) || 0;
            const opacity = Math.min(density / 100, 1);
            layer.setStyle({
              fillOpacity: opacity * 0.3,
              weight: 1
            });
          }
        });
      }
    });
    
    geoJsonLayer.addTo(this.hexagonLayer);
  };
  
  hexagonGrid.show();
  return hexagonGrid;
}

// Example 5: Hexagon grid with control panel
export function hexagonWithControlsExample(map, apiKey) {
  const hexagonGrid = createHexagonGrid(map, {
    apiEndpoint: `/api/v1/maps/hexagons?api_key=${apiKey}`,
    style: {
      fillColor: '#9b59b6',
      fillOpacity: 0.1,
      color: '#8e44ad',
      weight: 1,
      opacity: 0.5
    }
  });
  
  // Create custom control panel
  const HexagonControl = L.Control.extend({
    options: {
      position: 'topright'
    },
    
    onAdd: function(map) {
      const container = L.DomUtil.create('div', 'hexagon-control leaflet-bar');
      container.style.backgroundColor = 'white';
      container.style.padding = '10px';
      container.style.borderRadius = '4px';
      container.style.boxShadow = '0 1px 4px rgba(0,0,0,0.3)';
      
      container.innerHTML = `
        <div>
          <h4>Hexagon Grid</h4>
          <label>
            <input type="checkbox" id="hexagon-toggle"> Show Grid
          </label>
          <br>
          <label>
            Opacity: <input type="range" id="hexagon-opacity" min="10" max="100" value="50">
          </label>
          <br>
          <label>
            Color: <input type="color" id="hexagon-color" value="#9b59b6">
          </label>
        </div>
      `;
      
      // Prevent map interaction when using controls
      L.DomEvent.disableClickPropagation(container);
      
      // Add event listeners
      const toggleCheckbox = container.querySelector('#hexagon-toggle');
      const opacitySlider = container.querySelector('#hexagon-opacity');
      const colorPicker = container.querySelector('#hexagon-color');
      
      toggleCheckbox.addEventListener('change', (e) => {
        if (e.target.checked) {
          hexagonGrid.show();
        } else {
          hexagonGrid.hide();
        }
      });
      
      opacitySlider.addEventListener('input', (e) => {
        const opacity = parseInt(e.target.value) / 100;
        hexagonGrid.updateStyle({
          fillOpacity: opacity * 0.2,
          opacity: opacity
        });
      });
      
      colorPicker.addEventListener('change', (e) => {
        const color = e.target.value;
        hexagonGrid.updateStyle({
          fillColor: color,
          color: color
        });
      });
      
      return container;
    }
  });
  
  // Add the control to the map
  map.addControl(new HexagonControl());
  
  return hexagonGrid;
}

// Utility function to test API endpoint
export async function testHexagonAPI(apiKey, bounds = null) {
  const testBounds = bounds || {
    min_lon: -74.0,
    min_lat: 40.7,
    max_lon: -73.9,
    max_lat: 40.8
  };
  
  const params = new URLSearchParams({
    api_key: apiKey,
    ...testBounds
  });
  
  try {
    console.log('Testing hexagon API with bounds:', testBounds);
    
    const response = await fetch(`/api/v1/maps/hexagons?${params}`);
    const data = await response.json();
    
    if (response.ok) {
      console.log('API test successful:', {
        status: response.status,
        featureCount: data.features?.length || 0,
        firstFeature: data.features?.[0]
      });
      return data;
    } else {
      console.error('API test failed:', {
        status: response.status,
        error: data
      });
      return null;
    }
  } catch (error) {
    console.error('API test error:', error);
    return null;
  }
}

// Export all examples for easy testing
export const examples = {
  basic: basicHexagonExample,
  customStyled: customStyledHexagonExample,
  interactive: interactiveHexagonExample,
  dataVisualization: dataVisualizationHexagonExample,
  withControls: hexagonWithControlsExample
};