// Map control buttons and utilities
// This file contains all button controls that are positioned on the top-right corner of the map
import L from "leaflet";
import { applyThemeToButton } from "./theme_utils";

/**
 * Creates a standardized button element for map controls
 * @param {String} className - CSS class name for the button
 * @param {String} svgIcon - SVG icon HTML
 * @param {String} title - Button title/tooltip
 * @param {String} userTheme - User's theme preference ('dark' or 'light')
 * @param {Function} onClickCallback - Callback function to execute when button is clicked
 * @returns {HTMLElement} Button element with tooltip
 */
function createStandardButton(className, svgIcon, title, userTheme, onClickCallback) {
  const button = L.DomUtil.create('button', `${className} tooltip tooltip-left`);
  button.innerHTML = svgIcon;
  button.setAttribute('data-tip', title);

  // Apply standard button styling
  applyThemeToButton(button, userTheme);
  button.style.width = '48px';
  button.style.height = '48px';
  button.style.borderRadius = '4px';
  button.style.padding = '0';
  button.style.display = 'flex';
  button.style.alignItems = 'center';
  button.style.justifyContent = 'center';
  button.style.fontSize = '18px';
  button.style.transition = 'all 0.2s ease';

  // Disable map interactions when clicking the button
  L.DomEvent.disableClickPropagation(button);
  L.DomEvent.disableScrollPropagation(button);

  // Attach click handler if provided
  // Note: Some buttons (like Add Visit) have their handlers attached separately
  if (onClickCallback && typeof onClickCallback === 'function') {
    L.DomEvent.on(button, 'click', (e) => {
      L.DomEvent.stopPropagation(e);
      L.DomEvent.preventDefault(e);
      onClickCallback(button);
    });
  }

  return button;
}

/**
 * Creates a "Toggle Panel" button control for the map
 * @param {Function} onClickCallback - Callback function to execute when button is clicked
 * @param {String} userTheme - User's theme preference ('dark' or 'light')
 * @returns {L.Control} Leaflet control instance
 */
export function createTogglePanelControl(onClickCallback, userTheme = 'dark') {
  const TogglePanelControl = L.Control.extend({
    onAdd: function(map) {
      const svgIcon = `
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M8 2v4" />
          <path d="M16 2v4" />
          <path d="M21 14V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h8" />
          <path d="M3 10h18" />
          <path d="m16 20 2 2 4-4" />
        </svg>
      `;
      return createStandardButton('toggle-panel-button', svgIcon, 'Toggle Panel', userTheme, onClickCallback);
    }
  });

  return TogglePanelControl;
}

/**
 * Creates a "Visits Drawer" button control for the map
 * @param {Function} onClickCallback - Callback function to execute when button is clicked
 * @param {String} userTheme - User's theme preference ('dark' or 'light')
 * @returns {L.Control} Leaflet control instance
 */
export function createVisitsDrawerControl(onClickCallback, userTheme = 'dark') {
  const DrawerControl = L.Control.extend({
    onAdd: function(map) {
      const svgIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-panel-right-open-icon lucide-panel-right-open"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M15 3v18"/><path d="m10 15-3-3 3-3"/></svg>';
      return createStandardButton('leaflet-control-button drawer-button', svgIcon, 'Toggle Visits Drawer', userTheme, onClickCallback);
    }
  });

  return DrawerControl;
}

/**
 * Creates an "Area Selection" button control for the map
 * @param {Function} onClickCallback - Callback function to execute when button is clicked
 * @param {String} userTheme - User's theme preference ('dark' or 'light')
 * @returns {L.Control} Leaflet control instance
 */
export function createAreaSelectionControl(onClickCallback, userTheme = 'dark') {
  const SelectionControl = L.Control.extend({
    onAdd: function(map) {
      const svgIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-square-dashed-mouse-pointer-icon lucide-square-dashed-mouse-pointer"><path d="M12.034 12.681a.498.498 0 0 1 .647-.647l9 3.5a.5.5 0 0 1-.033.943l-3.444 1.068a1 1 0 0 0-.66.66l-1.067 3.443a.5.5 0 0 1-.943.033z"/><path d="M5 3a2 2 0 0 0-2 2"/><path d="M19 3a2 2 0 0 1 2 2"/><path d="M5 21a2 2 0 0 1-2-2"/><path d="M9 3h1"/><path d="M9 21h2"/><path d="M14 3h1"/><path d="M3 9v1"/><path d="M21 9v2"/><path d="M3 14v1"/></svg>';
      const button = createStandardButton('leaflet-bar leaflet-control leaflet-control-custom', svgIcon, 'Select Area', userTheme, onClickCallback);
      button.id = 'selection-tool-button';
      return button;
    }
  });

  return SelectionControl;
}

/**
 * Creates an "Add Visit" button control for the map
 * @param {Function} onClickCallback - Callback function to execute when button is clicked
 * @param {String} userTheme - User's theme preference ('dark' or 'light')
 * @returns {L.Control} Leaflet control instance
 */
export function createAddVisitControl(onClickCallback, userTheme = 'dark') {
  const AddVisitControl = L.Control.extend({
    onAdd: function(map) {
      const svgIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-map-pin-check-icon lucide-map-pin-check"><path d="M19.43 12.935c.357-.967.57-1.955.57-2.935a8 8 0 0 0-16 0c0 4.993 5.539 10.193 7.399 11.799a1 1 0 0 0 1.202 0 32.197 32.197 0 0 0 .813-.728"/><circle cx="12" cy="10" r="3"/><path d="m16 18 2 2 4-4"/></svg>';
      return createStandardButton('leaflet-control-button add-visit-button', svgIcon, 'Add a visit', userTheme, onClickCallback);
    }
  });

  return AddVisitControl;
}

/**
 * Creates a "Create Place" button control for the map
 * @param {Function} onClickCallback - Callback function to execute when button is clicked
 * @param {String} userTheme - User's theme preference ('dark' or 'light')
 * @returns {L.Control} Leaflet control instance
 */
export function createCreatePlaceControl(onClickCallback, userTheme = 'dark') {
  const CreatePlaceControl = L.Control.extend({
    onAdd: function(map) {
      const svgIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-map-pin-plus"><path d="M19.914 11.105A7.298 7.298 0 0 0 20 10a8 8 0 0 0-16 0c0 4.993 5.539 10.193 7.399 11.799a1 1 0 0 0 1.202 0 32 32 0 0 0 .824-.738"/><circle cx="12" cy="10" r="3"/><path d="M16 18h6"/><path d="M19 15v6"/></svg>';
      const button = createStandardButton('leaflet-control-button create-place-button', svgIcon, 'Create a place', userTheme, onClickCallback);
      button.id = 'create-place-btn';
      return button;
    }
  });

  return CreatePlaceControl;
}

/**
 * Adds all top-right corner buttons to the map in the correct order
 * Order: 1. Select Area, 2. Add Visit, 3. Create Place, 4. Open Calendar, 5. Open Drawer
 * Note: Layer control is added separately by Leaflet and appears at the top
 *
 * @param {Object} map - Leaflet map instance
 * @param {Object} callbacks - Object containing callback functions for each button
 * @param {Function} callbacks.onSelectArea - Callback for select area button
 * @param {Function} callbacks.onAddVisit - Callback for add visit button
 * @param {Function} callbacks.onCreatePlace - Callback for create place button
 * @param {Function} callbacks.onToggleCalendar - Callback for toggle calendar/panel button
 * @param {Function} callbacks.onToggleDrawer - Callback for toggle drawer button
 * @param {String} userTheme - User's theme preference ('dark' or 'light')
 * @returns {Object} Object containing references to all created controls
 */
export function addTopRightButtons(map, callbacks, userTheme = 'dark') {
  const controls = {};

  // 1. Select Area button
  if (callbacks.onSelectArea) {
    const SelectionControl = createAreaSelectionControl(callbacks.onSelectArea, userTheme);
    controls.selectionControl = new SelectionControl({ position: 'topright' });
    map.addControl(controls.selectionControl);
  }

  // 2. Add Visit button
  // Note: Button is always created, callback is optional (add_visit_controller attaches its own handler)
  const AddVisitControl = createAddVisitControl(callbacks.onAddVisit, userTheme);
  controls.addVisitControl = new AddVisitControl({ position: 'topright' });
  map.addControl(controls.addVisitControl);

  // 3. Create Place button
  if (callbacks.onCreatePlace) {
    const CreatePlaceControl = createCreatePlaceControl(callbacks.onCreatePlace, userTheme);
    controls.createPlaceControl = new CreatePlaceControl({ position: 'topright' });
    map.addControl(controls.createPlaceControl);
  }

  // 4. Open Calendar (Toggle Panel) button
  if (callbacks.onToggleCalendar) {
    const TogglePanelControl = createTogglePanelControl(callbacks.onToggleCalendar, userTheme);
    controls.togglePanelControl = new TogglePanelControl({ position: 'topright' });
    map.addControl(controls.togglePanelControl);
  }

  // 5. Open Drawer button
  if (callbacks.onToggleDrawer) {
    const DrawerControl = createVisitsDrawerControl(callbacks.onToggleDrawer, userTheme);
    controls.drawerControl = new DrawerControl({ position: 'topright' });
    map.addControl(controls.drawerControl);
  }

  return controls;
}

/**
 * Updates the Add Visit button to show active state
 * @param {HTMLElement} button - The button element to update
 */
export function setAddVisitButtonActive(button) {
  if (!button) return;

  button.style.backgroundColor = '#dc3545';
  button.style.color = 'white';
  button.innerHTML = '✕';
}

/**
 * Updates the Add Visit button to show inactive/default state
 * @param {HTMLElement} button - The button element to update
 * @param {String} userTheme - User's theme preference ('dark' or 'light')
 */
export function setAddVisitButtonInactive(button, userTheme = 'dark') {
  if (!button) return;

  applyThemeToButton(button, userTheme);
  button.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-map-pin-check-icon lucide-map-pin-check"><path d="M19.43 12.935c.357-.967.57-1.955.57-2.935a8 8 0 0 0-16 0c0 4.993 5.539 10.193 7.399 11.799a1 1 0 0 0 1.202 0 32.197 32.197 0 0 0 .813-.728"/><circle cx="12" cy="10" r="3"/><path d="m16 18 2 2 4-4"/></svg>';
}

/**
 * Updates the Create Place button to show active state
 * @param {HTMLElement} button - The button element to update
 */
export function setCreatePlaceButtonActive(button) {
  if (!button) return;

  button.style.backgroundColor = '#22c55e';
  button.style.color = 'white';
  button.style.border = '2px solid #16a34a';
  button.style.boxShadow = '0 0 12px rgba(34, 197, 94, 0.5)';
  button.innerHTML = '✕';
}

/**
 * Updates the Create Place button to show inactive/default state
 * @param {HTMLElement} button - The button element to update
 * @param {String} userTheme - User's theme preference ('dark' or 'light')
 */
export function setCreatePlaceButtonInactive(button, userTheme = 'dark') {
  if (!button) return;

  applyThemeToButton(button, userTheme);
  button.style.border = '';
  button.style.boxShadow = '';
  button.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-map-pin-plus"><path d="M19.914 11.105A7.298 7.298 0 0 0 20 10a8 8 0 0 0-16 0c0 4.993 5.539 10.193 7.399 11.799a1 1 0 0 0 1.202 0 32 32 0 0 0 .824-.738"/><circle cx="12" cy="10" r="3"/><path d="M16 18h6"/><path d="M19 15v6"/></svg>';
}
