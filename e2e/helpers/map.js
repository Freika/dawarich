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

  const checkbox = page.locator(`.leaflet-control-layers-overlays label:has-text("${layerName}") input[type="checkbox"]`);
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
