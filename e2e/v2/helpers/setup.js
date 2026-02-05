/**
 * Helper functions for Maps V2 E2E tests
 */

/**
 * Disable globe projection setting via API
 * This ensures consistent map rendering for E2E tests
 * @param {Page} page - Playwright page object
 */
export async function disableGlobeProjection(page) {
  // Get API key from the page (requires being logged in)
  const apiKey = await page.evaluate(() => {
    const metaTag = document.querySelector('meta[name="api-key"]');
    return metaTag?.content;
  });

  if (apiKey) {
    await page.request.patch('/api/v1/settings', {
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      data: {
        settings: {
          globe_projection: false
        }
      }
    });
  }
}

/**
 * Navigate to Maps V2 page
 * @param {Page} page - Playwright page object
 */
export async function navigateToMapsV2(page) {
  await page.goto('/map/v2');
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
    const element = document.querySelector('[data-controller*="maps--maplibre"]');
    if (!element) return false;
    const app = window.Stimulus || window.Application;
    if (!app) return false;
    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
    // Check if map exists and style is loaded (more reliable than loaded())
    return controller?.map && controller.map.isStyleLoaded();
  }, { timeout: 15000 });

  // Wait for loading overlay to be hidden
  await page.waitForFunction(() => {
    const loading = document.querySelector('[data-maps--maplibre-target="loading"]');
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
    const element = document.querySelector('[data-controller*="maps--maplibre"]');
    if (!element) return false;

    // Get Stimulus controller instance
    const app = window.Stimulus || window.Application;
    if (!app) return false;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
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
    const element = document.querySelector('[data-controller*="maps--maplibre"]');
    if (!element) return null;

    const app = window.Stimulus || window.Application;
    if (!app) return null;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
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
    const element = document.querySelector('[data-controller*="maps--maplibre"]');
    if (!element) return null;

    const app = window.Stimulus || window.Application;
    if (!app) return null;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
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
    const element = document.querySelector('[data-controller*="maps--maplibre"]');
    if (!element) return { hasSource: false, featureCount: 0, features: [] };

    const app = window.Stimulus || window.Application;
    if (!app) return { hasSource: false, featureCount: 0, features: [] };

    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
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
    const element = document.querySelector('[data-controller*="maps--maplibre"]');
    if (!element) return false;

    const app = window.Stimulus || window.Application;
    if (!app) return false;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
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
  const mapContainer = page.locator('[data-maps--maplibre-target="container"]');
  await mapContainer.click({ position: { x, y } });
}

/**
 * Wait for loading overlay to disappear
 * @param {Page} page - Playwright page object
 */
export async function waitForLoadingComplete(page) {
  await page.waitForFunction(() => {
    const loading = document.querySelector('[data-maps--maplibre-target="loading"]');
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
    const element = document.querySelector('[data-controller*="maps--maplibre"]');
    if (!element) return false;

    const app = window.Stimulus || window.Application;
    if (!app) return false;

    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
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
    const element = document.querySelector('[data-controller*="maps--maplibre"]');
    if (!element) return { hasSource: false, featureCount: 0, features: [] };

    const app = window.Stimulus || window.Application;
    if (!app) return { hasSource: false, featureCount: 0, features: [] };

    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
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

/**
 * Wait for settings panel to be visible
 * @param {Page} page - Playwright page object
 * @param {number} timeout - Timeout in milliseconds (default: 5000)
 */
export async function waitForSettingsPanel(page, timeout = 5000) {
  await page.waitForSelector('[data-maps--maplibre-target="settingsPanel"]', {
    state: 'visible',
    timeout
  });
}

/**
 * Wait for a specific tab to be active in settings panel
 * @param {Page} page - Playwright page object
 * @param {string} tabName - Tab name (e.g., 'layers', 'settings')
 * @param {number} timeout - Timeout in milliseconds (default: 5000)
 */
export async function waitForActiveTab(page, tabName, timeout = 5000) {
  await page.waitForFunction(
    (name) => {
      const tab = document.querySelector(`button[data-tab="${name}"]`);
      return tab?.getAttribute('aria-selected') === 'true';
    },
    tabName,
    { timeout }
  );
}

/**
 * Open settings panel and switch to a specific tab
 * @param {Page} page - Playwright page object
 * @param {string} tabName - Tab name (e.g., 'layers', 'settings')
 */
export async function openSettingsTab(page, tabName) {
  // Open settings panel
  const settingsButton = page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first();
  await settingsButton.click();
  await waitForSettingsPanel(page);

  // Click the desired tab
  const tabButton = page.locator(`button[data-tab="${tabName}"]`);
  await tabButton.click();
  await waitForActiveTab(page, tabName);
}

/**
 * Wait for a layer to exist on the map
 * @param {Page} page - Playwright page object
 * @param {string} layerId - Layer ID to wait for
 * @param {number} timeout - Timeout in milliseconds (default: 10000)
 */
export async function waitForLayer(page, layerId, timeout = 10000) {
  await page.waitForFunction(
    (id) => {
      const element = document.querySelector('[data-controller*="maps--maplibre"]');
      if (!element) return false;
      const app = window.Stimulus || window.Application;
      if (!app) return false;
      const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
      return controller?.map?.getLayer(id) !== undefined;
    },
    layerId,
    { timeout }
  );
}

/**
 * Wait for layer visibility to change
 * @param {Page} page - Playwright page object
 * @param {string} layerId - Layer ID
 * @param {boolean} expectedVisibility - Expected visibility state (true for visible, false for hidden)
 * @param {number} timeout - Timeout in milliseconds (default: 5000)
 */
export async function waitForLayerVisibility(page, layerId, expectedVisibility, timeout = 5000) {
  await page.waitForFunction(
    ({ id, visible }) => {
      const element = document.querySelector('[data-controller*="maps--maplibre"]');
      if (!element) return false;
      const app = window.Stimulus || window.Application;
      if (!app) return false;
      const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
      if (!controller?.map) return false;

      const visibility = controller.map.getLayoutProperty(id, 'visibility');
      const isVisible = visibility === 'visible' || visibility === undefined;
      return isVisible === visible;
    },
    { id: layerId, visible: expectedVisibility },
    { timeout }
  );
}

// ============================================================
// Timeline Panel Helpers
// ============================================================

/**
 * Open the timeline panel via Tools tab
 * @param {Page} page - Playwright page object
 * @param {boolean} closeSettingsPanel - Whether to close the settings panel after opening timeline (default: false)
 */
export async function openTimelinePanel(page, closeSettingsPanel = false) {
  // Open settings panel
  const settingsButton = page.locator('button[title="Open map settings"]')
  await settingsButton.click()
  await waitForSettingsPanel(page)

  // Click the tools tab
  const toolsTab = page.locator('button[data-tab="tools"]')
  await toolsTab.click()
  await page.waitForTimeout(300)

  // Click the Timeline button
  const timelineButton = page.locator('[data-tab-content="tools"] button:has-text("Timeline")')
  await timelineButton.click()
  await page.waitForTimeout(300)

  // Optionally close settings panel to avoid click interception
  if (closeSettingsPanel) {
    const closeButton = page.locator('button[title="Close panel"]')
    await closeButton.click()
    await page.waitForTimeout(200)
  }
}

/**
 * Wait for timeline panel to be visible
 * @param {Page} page - Playwright page object
 * @param {number} timeout - Timeout in milliseconds (default: 5000)
 */
export async function waitForTimelinePanel(page, timeout = 5000) {
  await page.waitForFunction(
    () => {
      const panel = document.querySelector('[data-maps--maplibre-target="timelinePanel"]')
      return panel && !panel.classList.contains('hidden')
    },
    { timeout }
  )
}

/**
 * Check if the timeline panel is visible
 * @param {Page} page - Playwright page object
 * @returns {Promise<boolean>}
 */
export async function isTimelinePanelVisible(page) {
  return await page.evaluate(() => {
    const panel = document.querySelector('[data-maps--maplibre-target="timelinePanel"]')
    return panel && !panel.classList.contains('hidden')
  })
}

/**
 * Get the current scrubber value
 * @param {Page} page - Playwright page object
 * @returns {Promise<number>}
 */
export async function getScrubberValue(page) {
  return await page.evaluate(() => {
    const scrubber = document.querySelector('[data-maps--maplibre-target="timelineScrubber"]')
    return scrubber ? parseInt(scrubber.value, 10) : -1
  })
}

/**
 * Set the scrubber value and trigger input event
 * @param {Page} page - Playwright page object
 * @param {number} minute - Minute value (0-1439)
 */
export async function setScrubberValue(page, minute) {
  await page.evaluate((min) => {
    const scrubber = document.querySelector('[data-maps--maplibre-target="timelineScrubber"]')
    if (scrubber) {
      scrubber.value = min
      scrubber.dispatchEvent(new Event('input', { bubbles: true }))
    }
  }, minute)
}

/**
 * Check if replay is currently active
 * @param {Page} page - Playwright page object
 * @returns {Promise<boolean>}
 */
export async function isReplayActive(page) {
  return await page.evaluate(() => {
    const element = document.querySelector('[data-controller*="maps--maplibre"]')
    if (!element) return false
    const app = window.Stimulus || window.Application
    if (!app) return false
    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
    return controller?.timelineReplayActive === true
  })
}

/**
 * Get timeline manager state from controller
 * @param {Page} page - Playwright page object
 * @returns {Promise<{hasData: boolean, dayCount: number, currentDayIndex: number, currentDayPointCount: number} | null>}
 */
export async function getTimelineState(page) {
  return await page.evaluate(() => {
    const element = document.querySelector('[data-controller*="maps--maplibre"]')
    if (!element) return null
    const app = window.Stimulus || window.Application
    if (!app) return null
    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
    if (!controller?.timelineManager) return null

    const tm = controller.timelineManager
    return {
      hasData: tm.hasData(),
      dayCount: tm.getDayCount(),
      currentDayIndex: tm.currentDayIndex,
      currentDayPointCount: tm.getCurrentDayPointCount()
    }
  })
}

/**
 * Get the timeline marker layer visibility and position
 * @param {Page} page - Playwright page object
 * @returns {Promise<{visible: boolean, coordinates: [number, number] | null}>}
 */
export async function getTimelineMarkerState(page) {
  return await page.evaluate(() => {
    const element = document.querySelector('[data-controller*="maps--maplibre"]')
    if (!element) return { visible: false, coordinates: null }
    const app = window.Stimulus || window.Application
    if (!app) return { visible: false, coordinates: null }
    const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
    if (!controller?.timelineMarkerLayer) return { visible: false, coordinates: null }

    const layer = controller.timelineMarkerLayer
    return {
      visible: layer.isVisible(),
      coordinates: layer.currentPosition || null
    }
  })
}

/**
 * Convert minute value (0-1439) to time string (HH:MM)
 * @param {number} minute - Minute value
 * @returns {string}
 */
export function minuteToTimeString(minute) {
  const hours = Math.floor(minute / 60)
  const mins = minute % 60
  return `${hours.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}`
}
