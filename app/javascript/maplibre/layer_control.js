// MapLibre Layer Control
// Provides UI for toggling map layers on/off

import { applyThemeToButton } from "../maps/theme_utils";

/**
 * Create and add layer control panel to map
 * @param {maplibregl.Map} map - MapLibre map instance
 * @param {Object} options - Configuration options
 * @returns {Object} Control instance with methods
 */
export function createLayerControl(map, options = {}) {
  const {
    userTheme = 'dark',
    position = 'top-right',
    initialLayers = {}
  } = options;

  // Track layer visibility state
  const layerState = {
    points: initialLayers.points !== false,
    routes: initialLayers.routes !== false
  };

  // Create control container
  const controlDiv = document.createElement('div');
  controlDiv.className = 'maplibre-layer-control';
  controlDiv.style.cssText = `
    position: absolute;
    ${position.includes('top') ? 'top: 10px;' : 'bottom: 10px;'}
    ${position.includes('right') ? 'right: 10px;' : 'left: 10px;'}
    z-index: 1000;
    background: ${userTheme === 'dark' ? '#1f2937' : '#ffffff'};
    border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.3);
    padding: 12px;
    min-width: 200px;
  `;

  // Create header
  const header = document.createElement('div');
  header.style.cssText = `
    font-weight: 600;
    font-size: 14px;
    color: ${userTheme === 'dark' ? '#f9fafb' : '#111827'};
    margin-bottom: 12px;
    padding-bottom: 8px;
    border-bottom: 1px solid ${userTheme === 'dark' ? '#374151' : '#e5e7eb'};
  `;
  header.textContent = 'Map Layers';

  // Create layers container
  const layersContainer = document.createElement('div');
  layersContainer.style.cssText = `
    display: flex;
    flex-direction: column;
    gap: 8px;
  `;

  // Create layer toggle items
  const layers = [
    { id: 'points', label: 'Points', icon: '📍' },
    { id: 'routes', label: 'Routes', icon: '🛣️' }
  ];

  const toggleButtons = {};

  layers.forEach(layer => {
    const item = createLayerItem(layer, layerState[layer.id], userTheme);
    layersContainer.appendChild(item.element);
    toggleButtons[layer.id] = item;

    // Add click handler
    item.element.addEventListener('click', () => {
      const newState = !layerState[layer.id];
      layerState[layer.id] = newState;
      toggleLayer(map, layer.id, newState);
      updateToggleButton(item, newState);
    });
  });

  // Assemble control
  controlDiv.appendChild(header);
  controlDiv.appendChild(layersContainer);

  // Add to map container
  map.getContainer().appendChild(controlDiv);

  // Return control instance
  return {
    element: controlDiv,
    layerState,
    toggleButtons,

    // Public methods
    toggleLayer: (layerId, visible) => {
      if (layerState.hasOwnProperty(layerId)) {
        layerState[layerId] = visible;
        toggleLayer(map, layerId, visible);
        updateToggleButton(toggleButtons[layerId], visible);
      }
    },

    getLayerState: (layerId) => {
      return layerState[layerId];
    },

    remove: () => {
      controlDiv.remove();
    },

    updateTheme: (newTheme) => {
      // Update control styling
      controlDiv.style.background = newTheme === 'dark' ? '#1f2937' : '#ffffff';
      header.style.color = newTheme === 'dark' ? '#f9fafb' : '#111827';
      header.style.borderColor = newTheme === 'dark' ? '#374151' : '#e5e7eb';

      // Update all layer items
      Object.values(toggleButtons).forEach(item => {
        updateItemTheme(item.element, newTheme);
      });
    }
  };
}

/**
 * Create a layer toggle item
 * @private
 */
function createLayerItem(layer, isVisible, userTheme) {
  const item = document.createElement('div');
  item.className = 'layer-item';
  item.style.cssText = `
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 12px;
    border-radius: 6px;
    cursor: pointer;
    background: ${userTheme === 'dark' ? '#374151' : '#f3f4f6'};
    transition: all 0.2s ease;
  `;

  // Hover effect
  item.addEventListener('mouseenter', () => {
    item.style.background = userTheme === 'dark' ? '#4b5563' : '#e5e7eb';
  });
  item.addEventListener('mouseleave', () => {
    item.style.background = userTheme === 'dark' ? '#374151' : '#f3f4f6';
  });

  // Label with icon
  const label = document.createElement('span');
  label.style.cssText = `
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    color: ${userTheme === 'dark' ? '#f9fafb' : '#111827'};
  `;
  label.innerHTML = `
    <span style="font-size: 16px;">${layer.icon}</span>
    <span>${layer.label}</span>
  `;

  // Toggle indicator
  const toggle = document.createElement('span');
  toggle.className = 'layer-toggle';
  toggle.style.cssText = `
    font-size: 18px;
    transition: transform 0.2s ease;
  `;
  toggle.textContent = isVisible ? '👁️' : '🚫';

  item.appendChild(label);
  item.appendChild(toggle);

  return {
    element: item,
    label,
    toggle
  };
}

/**
 * Update toggle button appearance
 * @private
 */
function updateToggleButton(item, isVisible) {
  item.toggle.textContent = isVisible ? '👁️' : '🚫';
  item.element.style.opacity = isVisible ? '1' : '0.6';
}

/**
 * Update item theme
 * @private
 */
function updateItemTheme(element, theme) {
  element.style.background = theme === 'dark' ? '#374151' : '#f3f4f6';
  const label = element.querySelector('span:last-child');
  if (label) {
    label.style.color = theme === 'dark' ? '#f9fafb' : '#111827';
  }
}

/**
 * Toggle layer visibility
 * @private
 */
function toggleLayer(map, layerId, visible) {
  console.log(`Toggling ${layerId} layer:`, visible ? 'ON' : 'OFF');

  switch (layerId) {
    case 'points':
      togglePointsLayer(map, visible);
      break;
    case 'routes':
      toggleRoutesLayer(map, visible);
      break;
  }
}

/**
 * Toggle points layer visibility
 * @private
 */
function togglePointsLayer(map, visible) {
  const layerId = 'points-layer';

  if (!map.getLayer(layerId)) {
    console.warn('Points layer not found');
    return;
  }

  map.setLayoutProperty(
    layerId,
    'visibility',
    visible ? 'visible' : 'none'
  );
}

/**
 * Toggle routes layer visibility
 * @private
 */
function toggleRoutesLayer(map, visible) {
  const mainLayerId = 'routes-layer';
  const hoverLayerId = 'routes-hover';

  if (!map.getLayer(mainLayerId)) {
    console.warn('Routes layer not found');
    return;
  }

  // Toggle main routes layer
  map.setLayoutProperty(
    mainLayerId,
    'visibility',
    visible ? 'visible' : 'none'
  );

  // Toggle hover layer if it exists
  if (map.getLayer(hoverLayerId)) {
    map.setLayoutProperty(
      hoverLayerId,
      'visibility',
      visible ? 'visible' : 'none'
    );
  }
}

/**
 * Add keyboard shortcuts for layer toggles
 * @param {Object} control - Layer control instance
 */
export function addLayerKeyboardShortcuts(control) {
  const handleKeyPress = (e) => {
    // Don't trigger if user is typing in an input
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
      return;
    }

    switch (e.key.toLowerCase()) {
      case 'p': // Toggle points
        control.toggleLayer('points', !control.getLayerState('points'));
        console.log('Toggled points with keyboard shortcut');
        break;
      case 'r': // Toggle routes
        control.toggleLayer('routes', !control.getLayerState('routes'));
        console.log('Toggled routes with keyboard shortcut');
        break;
    }
  };

  document.addEventListener('keydown', handleKeyPress);

  // Return cleanup function
  return () => {
    document.removeEventListener('keydown', handleKeyPress);
  };
}

/**
 * Create a compact layer control button (alternative compact UI)
 * @param {maplibregl.Map} map - MapLibre map instance
 * @param {Object} options - Configuration options
 * @returns {Object} Control instance
 */
export function createCompactLayerControl(map, options = {}) {
  const {
    userTheme = 'dark',
    position = 'top-right'
  } = options;

  // Track state
  const layerState = {
    points: true,
    routes: true,
    expanded: false
  };

  // Create container
  const container = document.createElement('div');
  container.style.cssText = `
    position: absolute;
    ${position.includes('top') ? 'top: 80px;' : 'bottom: 80px;'}
    ${position.includes('right') ? 'right: 10px;' : 'left: 10px;'}
    z-index: 1000;
  `;

  // Create toggle button
  const toggleBtn = document.createElement('button');
  toggleBtn.className = 'btn btn-sm btn-circle';
  applyThemeToButton(toggleBtn, userTheme);
  toggleBtn.innerHTML = '🗺️';
  toggleBtn.title = 'Toggle Layers (P=Points, R=Routes)';
  toggleBtn.style.cssText = `
    width: 48px;
    height: 48px;
    font-size: 20px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.3);
  `;

  // Create popup panel
  const panel = document.createElement('div');
  panel.style.cssText = `
    position: absolute;
    right: 58px;
    top: 0;
    background: ${userTheme === 'dark' ? '#1f2937' : '#ffffff'};
    border-radius: 8px;
    box-shadow: 0 2px 12px rgba(0,0,0,0.3);
    padding: 12px;
    display: none;
    min-width: 180px;
  `;

  // Create layer checkboxes
  const layersHTML = `
    <div style="margin-bottom: 12px; font-weight: 600; color: ${userTheme === 'dark' ? '#f9fafb' : '#111827'};">
      Layers
    </div>
    <div style="display: flex; flex-direction: column; gap: 8px;">
      <label class="flex items-center gap-2 cursor-pointer">
        <input type="checkbox" id="points-toggle" checked class="checkbox checkbox-sm">
        <span style="color: ${userTheme === 'dark' ? '#f9fafb' : '#111827'};">📍 Points (P)</span>
      </label>
      <label class="flex items-center gap-2 cursor-pointer">
        <input type="checkbox" id="routes-toggle" checked class="checkbox checkbox-sm">
        <span style="color: ${userTheme === 'dark' ? '#f9fafb' : '#111827'};">🛣️ Routes (R)</span>
      </label>
    </div>
  `;
  panel.innerHTML = layersHTML;

  // Assemble
  container.appendChild(toggleBtn);
  container.appendChild(panel);
  map.getContainer().appendChild(container);

  // Toggle button handler
  toggleBtn.addEventListener('click', () => {
    layerState.expanded = !layerState.expanded;
    panel.style.display = layerState.expanded ? 'block' : 'none';
  });

  // Checkbox handlers
  const pointsCheckbox = panel.querySelector('#points-toggle');
  const routesCheckbox = panel.querySelector('#routes-toggle');

  pointsCheckbox.addEventListener('change', (e) => {
    layerState.points = e.target.checked;
    togglePointsLayer(map, e.target.checked);
  });

  routesCheckbox.addEventListener('change', (e) => {
    layerState.routes = e.target.checked;
    toggleRoutesLayer(map, e.target.checked);
  });

  // Close panel when clicking outside
  document.addEventListener('click', (e) => {
    if (!container.contains(e.target) && layerState.expanded) {
      layerState.expanded = false;
      panel.style.display = 'none';
    }
  });

  return {
    element: container,
    layerState,

    toggleLayer: (layerId, visible) => {
      layerState[layerId] = visible;
      toggleLayer(map, layerId, visible);

      // Update checkbox
      if (layerId === 'points') {
        pointsCheckbox.checked = visible;
      } else if (layerId === 'routes') {
        routesCheckbox.checked = visible;
      }
    },

    remove: () => {
      container.remove();
    }
  };
}
