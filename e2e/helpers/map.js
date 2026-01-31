/**
 * Map helper functions for Playwright tests
 */

/**
 * Wait for Leaflet map to be fully initialized
 * @param {Page} page - Playwright page object
 */
export async function waitForMap(page) {
  await page.waitForFunction(() => {
    const container = document.querySelector('#map [data-maps-target="container"]');
    return container && container._leaflet_id !== undefined;
  }, { timeout: 10000 });
}

/**
 * Enable a map layer by name
 * @param {Page} page - Playwright page object
 * @param {string} layerName - Name of the layer to enable (e.g., "Routes", "Heatmap")
 */
export async function enableLayer(page, layerName) {
  await page.locator('.leaflet-control-layers').hover();
  await page.waitForTimeout(300);

  // Find the layer by its name in the tree structure
  // Layer names are in spans with class="leaflet-layerstree-header-name"
  // The checkbox is in the same .leaflet-layerstree-header container
  const layerHeader = page.locator(
    `.leaflet-layerstree-header:has(.leaflet-layerstree-header-name:text-is("${layerName}"))`
  ).first();

  const checkbox = layerHeader.locator('input[type="checkbox"]').first();

  const isChecked = await checkbox.isChecked();

  if (!isChecked) {
    await checkbox.check();
    await page.waitForTimeout(1000);
  }
}

/**
 * Click on the first confirmed visit circle on the map
 * @param {Page} page - Playwright page object
 * @returns {Promise<boolean>} - True if a visit was clicked, false otherwise
 */
export async function clickConfirmedVisit(page) {
  return await page.evaluate(() => {
    const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
    if (controller?.visitsManager?.confirmedVisitCircles?._layers) {
      const layers = controller.visitsManager.confirmedVisitCircles._layers;
      const firstVisit = Object.values(layers)[0];
      if (firstVisit) {
        firstVisit.fire('click');
        return true;
      }
    }
    return false;
  });
}

/**
 * Click on the first suggested visit circle on the map
 * @param {Page} page - Playwright page object
 * @returns {Promise<boolean>} - True if a visit was clicked, false otherwise
 */
export async function clickSuggestedVisit(page) {
  return await page.evaluate(() => {
    const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
    if (controller?.visitsManager?.suggestedVisitCircles?._layers) {
      const layers = controller.visitsManager.suggestedVisitCircles._layers;
      const firstVisit = Object.values(layers)[0];
      if (firstVisit) {
        firstVisit.fire('click');
        return true;
      }
    }
    return false;
  });
}

/**
 * Get current map zoom level
 * @param {Page} page - Playwright page object
 * @returns {Promise<number|null>} - Current zoom level or null
 */
export async function getMapZoom(page) {
  return await page.evaluate(() => {
    const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
    return controller?.map?.getZoom() || null;
  });
}

/**
 * Open the settings panel by clicking the gear button
 * @param {Page} page - Playwright page object
 */
export async function openSettingsPanel(page) {
  await page.locator('.map-settings-button').click();
  await page.waitForSelector('.leaflet-settings-panel', { state: 'visible', timeout: 5000 });
}

/**
 * Close the settings panel by clicking the gear button again
 * @param {Page} page - Playwright page object
 */
export async function closeSettingsPanel(page) {
  await page.locator('.map-settings-button').click();
  await page.waitForSelector('.leaflet-settings-panel', { state: 'detached', timeout: 5000 });
}

/**
 * Hover over the first route polyline segment to trigger popup
 * @param {Page} page - Playwright page object
 * @returns {Promise<boolean>} - True if a route was hovered, false otherwise
 */
export async function hoverFirstRoute(page) {
  return await page.evaluate(() => {
    const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
    if (!controller?.polylinesLayer) return false;
    let hovered = false;
    controller.polylinesLayer.eachLayer((layer) => {
      if (hovered) return;
      if (layer._layers) {
        Object.values(layer._layers).forEach((segment) => {
          if (hovered) return;
          const latlngs = segment.getLatLngs?.();
          if (latlngs?.length > 0) {
            segment.fire('mouseover', { latlng: latlngs[0] });
            hovered = true;
          }
        });
      }
    });
    return hovered;
  });
}

/**
 * Wait for MapLibre map (Maps V2) to be fully initialized
 * @param {Page} page - Playwright page object
 */
export async function waitForMapLoad(page) {
  await page.waitForFunction(() => {
    return window.map && window.map.loaded();
  }, { timeout: 10000 });

  // Wait for initial data load to complete
  await page.waitForSelector('[data-maps--maplibre-target="loading"].hidden', { timeout: 15000 });
}
