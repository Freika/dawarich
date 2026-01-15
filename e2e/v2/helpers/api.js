/**
 * API helper functions for e2e tests
 * Used for sending location data via OwnTracks protocol
 */

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

/**
 * Send a location point via OwnTracks API
 * @param {import('@playwright/test').APIRequestContext} request - Playwright request context
 * @param {string} apiKey - User's API key
 * @param {number} lat - Latitude
 * @param {number} lon - Longitude
 * @param {number} [timestamp] - Unix timestamp (defaults to current time)
 * @param {Object} [options] - Additional point options
 * @returns {Promise<import('@playwright/test').APIResponse>}
 */
export async function sendOwnTracksPoint(request, apiKey, lat, lon, timestamp, options = {}) {
  const tst = timestamp || Math.floor(Date.now() / 1000);

  const pointData = {
    _type: 'location',
    lat,
    lon,
    tst,
    acc: options.accuracy || 10,
    batt: options.battery || 85,
    vel: options.velocity || 0,
    alt: options.altitude || 0,
    tid: options.trackerId || 'e2e'
  };

  const response = await request.post(`${BASE_URL}/api/v1/owntracks/points?api_key=${apiKey}`, {
    data: pointData,
    headers: {
      'Content-Type': 'application/json'
    }
  });

  return response;
}

/**
 * Wait for a point to appear on the map at the specified coordinates
 * @param {import('@playwright/test').Page} page - Playwright page
 * @param {number} expectedLat - Expected latitude
 * @param {number} expectedLon - Expected longitude
 * @param {number} [timeout=15000] - Timeout in milliseconds
 * @param {number} [tolerance=0.0001] - Coordinate tolerance for matching
 * @returns {Promise<boolean>}
 */
export async function waitForPointOnMap(page, expectedLat, expectedLon, timeout = 15000, tolerance = 0.0001) {
  try {
    await page.waitForFunction(
      ({ lat, lon, tol }) => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]');
        if (!element) return false;

        const app = window.Stimulus || window.Application;
        if (!app) return false;

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
        if (!controller?.map) return false;

        // Check points source for the new point
        const source = controller.map.getSource('points-source');
        if (!source) return false;

        const data = source._data;
        if (!data?.features) return false;

        // Look for a point matching our coordinates
        return data.features.some(feature => {
          const coords = feature.geometry?.coordinates;
          if (!coords) return false;

          const [pointLon, pointLat] = coords;
          return Math.abs(pointLat - lat) < tol && Math.abs(pointLon - lon) < tol;
        });
      },
      { lat: expectedLat, lon: expectedLon, tol: tolerance },
      { timeout }
    );
    return true;
  } catch {
    return false;
  }
}

/**
 * Wait for a family member location to appear on the map
 * @param {import('@playwright/test').Page} page - Playwright page
 * @param {string} memberEmail - Family member's email
 * @param {number} [timeout=15000] - Timeout in milliseconds
 * @returns {Promise<boolean>}
 */
export async function waitForFamilyMemberOnMap(page, memberEmail, timeout = 15000) {
  try {
    await page.waitForFunction(
      (email) => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]');
        if (!element) return false;

        const app = window.Stimulus || window.Application;
        if (!app) return false;

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
        if (!controller?.map) return false;

        // Check family layer source for the member
        const source = controller.map.getSource('family-source');
        if (!source) return false;

        const data = source._data;
        if (!data?.features) return false;

        // Look for a feature with matching email in properties
        return data.features.some(feature => {
          return feature.properties?.email === email;
        });
      },
      memberEmail,
      { timeout }
    );
    return true;
  } catch {
    return false;
  }
}

/**
 * Wait for the recent point layer to be visible and showing a point
 * @param {import('@playwright/test').Page} page - Playwright page
 * @param {number} [timeout=15000] - Timeout in milliseconds
 * @returns {Promise<boolean>}
 */
export async function waitForRecentPointVisible(page, timeout = 15000) {
  try {
    await page.waitForFunction(
      () => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]');
        if (!element) return false;

        const app = window.Stimulus || window.Application;
        if (!app) return false;

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
        if (!controller?.layerManager) return false;

        const recentPointLayer = controller.layerManager.getLayer('recentPoint');
        if (!recentPointLayer) return false;

        // Check if layer is visible and has data
        return recentPointLayer.visible === true;
      },
      { timeout }
    );
    return true;
  } catch {
    return false;
  }
}

/**
 * Enable live mode via the settings toggle
 * @param {import('@playwright/test').Page} page - Playwright page
 * @returns {Promise<void>}
 */
export async function enableLiveMode(page) {
  // Open settings panel
  await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click();
  await page.waitForTimeout(300);

  // Click Settings tab
  await page.locator('button[data-tab="settings"]').click();
  await page.waitForTimeout(300);

  // Enable live mode if not already enabled
  const liveModeToggle = page.locator('[data-maps--maplibre-realtime-target="liveModeToggle"]');
  if (!await liveModeToggle.isChecked()) {
    await liveModeToggle.click();
    await page.waitForTimeout(500);
  }

  // Close settings
  await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click();
  await page.waitForTimeout(300);
}

/**
 * Wait for ActionCable connection to be established
 * @param {import('@playwright/test').Page} page - Playwright page
 * @param {number} [timeout=10000] - Timeout in milliseconds
 * @returns {Promise<boolean>}
 */
export async function waitForActionCableConnection(page, timeout = 10000) {
  try {
    await page.waitForFunction(
      () => {
        const element = document.querySelector('[data-controller*="maps--maplibre-realtime"]');
        if (!element) return false;

        const app = window.Stimulus || window.Application;
        if (!app) return false;

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre-realtime');
        if (!controller?.channels) return false;

        // Check if we have at least one active channel
        return controller.channels !== undefined;
      },
      { timeout }
    );
    return true;
  } catch {
    return false;
  }
}

/**
 * Wait for the PointsChannel to be connected and active
 * @param {import('@playwright/test').Page} page - Playwright page
 * @param {number} [timeout=10000] - Timeout in milliseconds
 * @returns {Promise<boolean>}
 */
export async function waitForPointsChannelConnected(page, timeout = 10000) {
  try {
    await page.waitForFunction(
      () => {
        const element = document.querySelector('[data-controller*="maps--maplibre-realtime"]');
        if (!element) return false;

        const app = window.Stimulus || window.Application;
        if (!app) return false;

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre-realtime');
        if (!controller?.channels?.subscriptions?.points) return false;

        // Check if the points channel subscription exists
        const pointsSub = controller.channels.subscriptions.points;
        return pointsSub !== null && pointsSub !== undefined;
      },
      { timeout }
    );
    return true;
  } catch {
    return false;
  }
}

/**
 * Get the current point count on the map
 * @param {import('@playwright/test').Page} page - Playwright page
 * @returns {Promise<number>}
 */
export async function getPointCount(page) {
  return await page.evaluate(() => {
    const element = document.querySelector('[data-controller*="maps--maplibre"]');
    if (!element) return 0;

    const app = window.Stimulus || window.Application;
    if (!app) return 0;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
    if (!controller?.map) return 0;

    const source = controller.map.getSource('points-source');
    if (!source?._data?.features) return 0;

    return source._data.features.length;
  });
}
