/**
 * Integration script for adding hexagon grid to the existing maps controller
 * This file provides the integration code to be added to maps_controller.js
 */

import { createHexagonGrid } from './hexagon_grid';

// Add this to the maps_controller.js connect() method after line 240 (after live map initialization)
export function initializeHexagonGrid(controller) {
  // Create hexagon grid instance
  controller.hexagonGrid = createHexagonGrid(controller.map, {
    apiEndpoint: `/api/v1/maps/hexagons?api_key=${controller.apiKey}`,
    style: {
      fillColor: '#3388ff',
      fillOpacity: 0.1,
      color: '#3388ff',
      weight: 1,
      opacity: 0.5
    },
    debounceDelay: 300,
    maxZoom: 16, // Don't show hexagons beyond this zoom
    minZoom: 8   // Don't show hexagons below this zoom
  });

  return controller.hexagonGrid;
}

// Add this to the controlsLayer object in maps_controller.js (around line 194-205)
export function addHexagonToLayerControl(controller) {
  // This should be added to the controlsLayer object:
  // "Hexagon Grid": controller.hexagonGrid?.hexagonLayer || L.layerGroup()

  return {
    "Hexagon Grid": controller.hexagonGrid?.hexagonLayer || L.layerGroup()
  };
}

// Add this to the disconnect() method cleanup
export function cleanupHexagonGrid(controller) {
  if (controller.hexagonGrid) {
    controller.hexagonGrid.destroy();
  }
}

// Settings panel integration - add this to the settings form HTML (around line 843)
export const hexagonSettingsHTML = `
  <label for="hexagon_grid_enabled">
    Hexagon Grid
    <label for="hexagon_grid_enabled_info" class="btn-xs join-item inline">?</label>
    <input type="checkbox" id="hexagon_grid_enabled" name="hexagon_grid_enabled" class='w-4' style="width: 20px;" />
  </label>
  <label for="hexagon_opacity">Hexagon Opacity, %</label>
  <div class="join">
    <input type="number" class="input input-ghost join-item focus:input-ghost input-xs input-bordered w-full max-w-xs" id="hexagon_opacity" name="hexagon_opacity" min="10" max="100" step="10" value="50">
    <label for="hexagon_opacity_info" class="btn-xs join-item">?</label>
  </div>
`;

// Settings update handler - add this to updateSettings method
export function updateHexagonSettings(controller, event) {
  const hexagonEnabled = event.target.hexagon_grid_enabled?.checked || false;
  const hexagonOpacity = (parseInt(event.target.hexagon_opacity?.value) || 50) / 100;

  if (controller.hexagonGrid) {
    if (hexagonEnabled) {
      controller.hexagonGrid.show();
      controller.hexagonGrid.updateStyle({
        fillOpacity: hexagonOpacity * 0.2, // Scale down for fill
        opacity: hexagonOpacity
      });
    } else {
      controller.hexagonGrid.hide();
    }
  }

  // Return the settings object to be sent to the server
  return {
    hexagon_grid_enabled: hexagonEnabled,
    hexagon_opacity: hexagonOpacity
  };
}

// Layer control event handlers - add these to the overlayadd/overlayremove event listeners
export function handleHexagonLayerEvents(controller, event) {
  if (event.name === 'Hexagon Grid') {
    if (event.type === 'overlayadd') {
      console.log('Hexagon Grid layer enabled via layer control');
      if (controller.hexagonGrid) {
        controller.hexagonGrid.show();
      }
    } else if (event.type === 'overlayremove') {
      console.log('Hexagon Grid layer disabled via layer control');
      if (controller.hexagonGrid) {
        controller.hexagonGrid.hide();
      }
    }
  }
}
