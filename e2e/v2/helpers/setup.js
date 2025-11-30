/**
 * Helper functions for Maps V2 E2E tests
 */

/**
 * Navigate to Maps V2 page
 * @param {Page} page - Playwright page object
 */
export async function navigateToMapsV2(page) {
  await page.goto('/maps_v2');
}

/**
 * Navigate to Maps V2 with specific date range
 * @param {Page} page - Playwright page object
 * @param {string} startDate - Start date in format 'YYYY-MM-DDTHH:mm'
 * @param {string} endDate - End date in format 'YYYY-MM-DDTHH:mm'
 */
export async function navigateToMapsV2WithDate(page, startDate, endDate) {
  const startInput = page.locator('input[type="datetime-local"][name="start_at"]');
  await startInput.clear();
  await startInput.fill(startDate);

  const endInput = page.locator('input[type="datetime-local"][name="end_at"]');
  await endInput.clear();
  await endInput.fill(endDate);

  await page.click('input[type="submit"][value="Search"]');
  await page.waitForLoadState('networkidle');

  // Wait for MapLibre to initialize after page reload
  await waitForMapLibre(page);
  await page.waitForTimeout(500);
}

/**
 * Wait for MapLibre map to be fully initialized
 * @param {Page} page - Playwright page object
 * @param {number} timeout - Timeout in milliseconds (default: 10000)
 */
export async function waitForMapLibre(page, timeout = 10000) {
  // Wait for canvas to appear
  await page.waitForSelector('.maplibregl-canvas', { timeout });

  // Wait for map instance to exist and style to be loaded
  await page.waitForFunction(() => {
    const element = document.querySelector('[data-controller*="maps-v2"]');
    if (!element) return false;
    const app = window.Stimulus || window.Application;
    if (!app) return false;
    const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
    // Check if map exists and style is loaded (more reliable than loaded())
    return controller?.map && controller.map.isStyleLoaded();
  }, { timeout: 15000 });

  // Wait for loading overlay to be hidden
  await page.waitForFunction(() => {
    const loading = document.querySelector('[data-maps-v2-target="loading"]');
    return loading && loading.classList.contains('hidden');
  }, { timeout: 15000 });
}

/**
 * Get map instance from page
 * @param {Page} page - Playwright page object
 * @returns {Promise<boolean>} - True if map exists
 */
export async function hasMapInstance(page) {
  return await page.evaluate(() => {
    const element = document.querySelector('[data-controller*="maps-v2"]');
    if (!element) return false;

    // Get Stimulus controller instance
    const app = window.Stimulus || window.Application;
    if (!app) return false;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
    return controller && controller.map !== undefined;
  });
}

/**
 * Get current map zoom level
 * @param {Page} page - Playwright page object
 * @returns {Promise<number|null>} - Current zoom level or null
 */
export async function getMapZoom(page) {
  return await page.evaluate(() => {
    const element = document.querySelector('[data-controller*="maps-v2"]');
    if (!element) return null;

    const app = window.Stimulus || window.Application;
    if (!app) return null;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
    return controller?.map?.getZoom() || null;
  });
}

/**
 * Get map center coordinates
 * @param {Page} page - Playwright page object
 * @returns {Promise<{lng: number, lat: number}|null>}
 */
export async function getMapCenter(page) {
  return await page.evaluate(() => {
    const element = document.querySelector('[data-controller*="maps-v2"]');
    if (!element) return null;

    const app = window.Stimulus || window.Application;
    if (!app) return null;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
    if (!controller?.map) return null;

    const center = controller.map.getCenter();
    return { lng: center.lng, lat: center.lat };
  });
}

/**
 * Get points source data from map
 * @param {Page} page - Playwright page object
 * @returns {Promise<{hasSource: boolean, featureCount: number}>}
 */
export async function getPointsSourceData(page) {
  return await page.evaluate(() => {
    const element = document.querySelector('[data-controller*="maps-v2"]');
    if (!element) return { hasSource: false, featureCount: 0, features: [] };

    const app = window.Stimulus || window.Application;
    if (!app) return { hasSource: false, featureCount: 0, features: [] };

    const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
    if (!controller?.map) return { hasSource: false, featureCount: 0, features: [] };

    const source = controller.map.getSource('points-source');
    if (!source) return { hasSource: false, featureCount: 0, features: [] };

    const data = source._data;
    return {
      hasSource: true,
      featureCount: data?.features?.length || 0,
      features: data?.features || []
    };
  });
}

/**
 * Check if a layer exists on the map
 * @param {Page} page - Playwright page object
 * @param {string} layerId - Layer ID to check
 * @returns {Promise<boolean>}
 */
export async function hasLayer(page, layerId) {
  return await page.evaluate((id) => {
    const element = document.querySelector('[data-controller*="maps-v2"]');
    if (!element) return false;

    const app = window.Stimulus || window.Application;
    if (!app) return false;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
    if (!controller?.map) return false;

    return controller.map.getLayer(id) !== undefined;
  }, layerId);
}

/**
 * Click on map at specific pixel coordinates
 * @param {Page} page - Playwright page object
 * @param {number} x - X coordinate
 * @param {number} y - Y coordinate
 */
export async function clickMapAt(page, x, y) {
  const mapContainer = page.locator('[data-maps-v2-target="container"]');
  await mapContainer.click({ position: { x, y } });
}

/**
 * Wait for loading overlay to disappear
 * @param {Page} page - Playwright page object
 */
export async function waitForLoadingComplete(page) {
  await page.waitForFunction(() => {
    const loading = document.querySelector('[data-maps-v2-target="loading"]');
    return loading && loading.classList.contains('hidden');
  }, { timeout: 15000 });
}

/**
 * Check if popup is visible
 * @param {Page} page - Playwright page object
 * @returns {Promise<boolean>}
 */
export async function hasPopup(page) {
  const popup = page.locator('.maplibregl-popup');
  return await popup.isVisible().catch(() => false);
}

/**
 * Get layer visibility state
 * @param {Page} page - Playwright page object
 * @param {string} layerId - Layer ID
 * @returns {Promise<boolean>} - True if visible, false if hidden
 */
export async function getLayerVisibility(page, layerId) {
  return await page.evaluate((id) => {
    const element = document.querySelector('[data-controller*="maps-v2"]');
    if (!element) return false;

    const app = window.Stimulus || window.Application;
    if (!app) return false;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
    if (!controller?.map) return false;

    const visibility = controller.map.getLayoutProperty(id, 'visibility');
    return visibility === 'visible' || visibility === undefined;
  }, layerId);
}

/**
 * Get routes source data from map
 * @param {Page} page - Playwright page object
 * @returns {Promise<{hasSource: boolean, featureCount: number, features: Array}>}
 */
export async function getRoutesSourceData(page) {
  return await page.evaluate(() => {
    const element = document.querySelector('[data-controller*="maps-v2"]');
    if (!element) return { hasSource: false, featureCount: 0, features: [] };

    const app = window.Stimulus || window.Application;
    if (!app) return { hasSource: false, featureCount: 0, features: [] };

    const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
    if (!controller?.map) return { hasSource: false, featureCount: 0, features: [] };

    const source = controller.map.getSource('routes-source');
    if (!source) return { hasSource: false, featureCount: 0, features: [] };

    const data = source._data;
    return {
      hasSource: true,
      featureCount: data?.features?.length || 0,
      features: data?.features || []
    };
  });
}
