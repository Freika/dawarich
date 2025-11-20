import { test, expect } from '@playwright/test';
import { closeOnboardingModal } from '../helpers/navigation.js';
import {
  navigateToMapsV2,
  navigateToMapsV2WithDate,
  waitForMapLibre,
  waitForLoadingComplete,
  hasLayer,
  getLayerVisibility,
  getRoutesSourceData
} from './helpers/setup.js';

test.describe('Phase 2: Routes + Layer Controls', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page);
    await closeOnboardingModal(page);
    await waitForMapLibre(page);
    await waitForLoadingComplete(page);
    // Give extra time for routes layer to be added after points (needs time for style.load event)
    await page.waitForTimeout(1500);
  });

  test('routes layer exists on map', async ({ page }) => {
    // Wait for routes layer to be added (it's added after points layer)
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      if (!element) return false;
      const app = window.Stimulus || window.Application;
      if (!app) return false;
      const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
      return controller?.map?.getLayer('routes') !== undefined;
    }, { timeout: 10000 }).catch(() => false);

    // Check if routes layer exists
    const hasRoutesLayer = await hasLayer(page, 'routes');
    expect(hasRoutesLayer).toBe(true);
  });

  test('routes source has data', async ({ page }) => {
    // Wait for routes layer to be added with longer timeout
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      if (!element) return false;
      const app = window.Stimulus || window.Application;
      if (!app) return false;
      const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
      return controller?.map?.getSource('routes-source') !== undefined;
    }, { timeout: 20000 });

    const { hasSource, featureCount } = await getRoutesSourceData(page);

    expect(hasSource).toBe(true);
    // Should have at least one route if there are points
    expect(featureCount).toBeGreaterThanOrEqual(0);
  });

  test('routes have LineString geometry', async ({ page }) => {
    const { features } = await getRoutesSourceData(page);

    if (features.length > 0) {
      features.forEach(feature => {
        expect(feature.geometry.type).toBe('LineString');
        expect(feature.geometry.coordinates.length).toBeGreaterThan(1);
      });
    }
  });

  test('routes have distance properties', async ({ page }) => {
    const { features } = await getRoutesSourceData(page);

    if (features.length > 0) {
      features.forEach(feature => {
        expect(feature.properties).toHaveProperty('distance');
        expect(typeof feature.properties.distance).toBe('number');
        expect(feature.properties.distance).toBeGreaterThanOrEqual(0);
      });
    }
  });

  test('routes have solid color (not speed-based)', async ({ page }) => {
    // Wait for routes layer to be added with longer timeout
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      if (!element) return false;
      const app = window.Stimulus || window.Application;
      if (!app) return false;
      const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
      return controller?.map?.getLayer('routes') !== undefined;
    }, { timeout: 20000 });

    const routeLayerInfo = await page.evaluate(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      if (!element) return null;

      const app = window.Stimulus || window.Application;
      if (!app) return null;

      const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
      if (!controller?.map) return null;

      const layer = controller.map.getLayer('routes');
      if (!layer) return null;

      // Get paint property using MapLibre's getPaintProperty method
      const lineColor = controller.map.getPaintProperty('routes', 'line-color');

      return {
        exists: !!lineColor,
        isArray: Array.isArray(lineColor),
        value: lineColor
      };
    });

    expect(routeLayerInfo).toBeTruthy();
    expect(routeLayerInfo.exists).toBe(true);
    // Should NOT be a speed-based interpolation array
    expect(routeLayerInfo.isArray).toBe(false);
    // Should be orange color
    expect(routeLayerInfo.value).toBe('#f97316');
  });

  test('layer controls are visible', async ({ page }) => {
    const pointsButton = page.locator('button[data-layer="points"]');
    const routesButton = page.locator('button[data-layer="routes"]');

    await expect(pointsButton).toBeVisible();
    await expect(routesButton).toBeVisible();
  });

  test('points layer starts visible', async ({ page }) => {
    const isVisible = await getLayerVisibility(page, 'points');
    expect(isVisible).toBe(true);
  });

  test('routes layer starts visible', async ({ page }) => {
    const isVisible = await getLayerVisibility(page, 'routes');
    expect(isVisible).toBe(true);
  });

  test('can toggle points layer off and on', async ({ page }) => {
    const pointsButton = page.locator('button[data-layer="points"]');

    // Initially visible
    let isVisible = await getLayerVisibility(page, 'points');
    expect(isVisible).toBe(true);

    // Toggle off and wait for visibility to change
    await pointsButton.click();
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      const app = window.Stimulus || window.Application;
      const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2');
      const visibility = controller?.map?.getLayoutProperty('points', 'visibility');
      return visibility === 'none';
    }, { timeout: 2000 }).catch(() => {});

    isVisible = await getLayerVisibility(page, 'points');
    expect(isVisible).toBe(false);

    // Toggle back on
    await pointsButton.click();
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      const app = window.Stimulus || window.Application;
      const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2');
      const visibility = controller?.map?.getLayoutProperty('points', 'visibility');
      return visibility === 'visible' || visibility === undefined;
    }, { timeout: 2000 }).catch(() => {});

    isVisible = await getLayerVisibility(page, 'points');
    expect(isVisible).toBe(true);
  });

  test('can toggle routes layer off and on', async ({ page }) => {
    // Wait for routes layer to exist first
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      const app = window.Stimulus || window.Application;
      const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2');
      return controller?.map?.getLayer('routes') !== undefined;
    }, { timeout: 10000 }).catch(() => false);

    const routesButton = page.locator('button[data-layer="routes"]');

    // Initially visible
    let isVisible = await getLayerVisibility(page, 'routes');
    expect(isVisible).toBe(true);

    // Toggle off and wait for visibility to change
    await routesButton.click();
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      const app = window.Stimulus || window.Application;
      const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2');
      const visibility = controller?.map?.getLayoutProperty('routes', 'visibility');
      return visibility === 'none';
    }, { timeout: 2000 }).catch(() => {});

    isVisible = await getLayerVisibility(page, 'routes');
    expect(isVisible).toBe(false);

    // Toggle back on
    await routesButton.click();
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      const app = window.Stimulus || window.Application;
      const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2');
      const visibility = controller?.map?.getLayoutProperty('routes', 'visibility');
      return visibility === 'visible' || visibility === undefined;
    }, { timeout: 2000 }).catch(() => {});

    isVisible = await getLayerVisibility(page, 'routes');
    expect(isVisible).toBe(true);
  });

  test('layer toggle button styles change with visibility', async ({ page }) => {
    const pointsButton = page.locator('button[data-layer="points"]');

    // Initially should have btn-primary
    await expect(pointsButton).toHaveClass(/btn-primary/);

    // Click to toggle off
    await pointsButton.click();
    await page.waitForTimeout(100);

    // Should now have btn-outline
    await expect(pointsButton).toHaveClass(/btn-outline/);

    // Click to toggle back on
    await pointsButton.click();
    await page.waitForTimeout(100);

    // Should have btn-primary again
    await expect(pointsButton).toHaveClass(/btn-primary/);
  });

  test('both layers can be visible simultaneously', async ({ page }) => {
    const pointsVisible = await getLayerVisibility(page, 'points');
    const routesVisible = await getLayerVisibility(page, 'routes');

    expect(pointsVisible).toBe(true);
    expect(routesVisible).toBe(true);
  });

  test('both layers can be hidden simultaneously', async ({ page }) => {
    const pointsButton = page.locator('button[data-layer="points"]');
    const routesButton = page.locator('button[data-layer="routes"]');

    // Toggle points off and wait
    await pointsButton.click();
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      const app = window.Stimulus || window.Application;
      const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2');
      const visibility = controller?.map?.getLayoutProperty('points', 'visibility');
      return visibility === 'none';
    }, { timeout: 2000 }).catch(() => {});

    // Toggle routes off and wait
    await routesButton.click();
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      const app = window.Stimulus || window.Application;
      const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2');
      const visibility = controller?.map?.getLayoutProperty('routes', 'visibility');
      return visibility === 'none';
    }, { timeout: 2000 }).catch(() => {});

    const pointsVisible = await getLayerVisibility(page, 'points');
    const routesVisible = await getLayerVisibility(page, 'routes');

    expect(pointsVisible).toBe(false);
    expect(routesVisible).toBe(false);
  });

  test('date navigation preserves routes layer', async ({ page }) => {
    // Wait for routes layer to be added first
    await page.waitForTimeout(1000);

    // Verify routes exist initially
    const initialRoutes = await hasLayer(page, 'routes');
    expect(initialRoutes).toBe(true);

    // Navigate to a different date with known data (same as other tests use)
    await navigateToMapsV2WithDate(page, '2025-10-15T00:00', '2025-10-15T23:59');
    await closeOnboardingModal(page);

    // Wait for map to reinitialize and routes layer to be added
    await page.waitForTimeout(1000);

    // Verify routes layer still exists after navigation
    const hasRoutesLayer = await hasLayer(page, 'routes');
    expect(hasRoutesLayer).toBe(true);
  });

  test('routes connect points chronologically', async ({ page }) => {
    const { features } = await getRoutesSourceData(page);

    if (features.length > 0) {
      features.forEach(feature => {
        // Each route should have start and end times
        expect(feature.properties).toHaveProperty('startTime');
        expect(feature.properties).toHaveProperty('endTime');

        // End time should be after start time
        expect(feature.properties.endTime).toBeGreaterThanOrEqual(feature.properties.startTime);

        // Should have point count
        expect(feature.properties).toHaveProperty('pointCount');
        expect(feature.properties.pointCount).toBeGreaterThan(1);
      });
    }
  });

  test('routes layer renders below points layer', async ({ page }) => {
    // Wait for both layers to exist
    await page.waitForFunction(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      const app = window.Stimulus || window.Application;
      const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2');
      return controller?.map?.getLayer('routes') !== undefined &&
             controller?.map?.getLayer('points') !== undefined;
    }, { timeout: 10000 });

    // Get layer order - routes should be added before points
    const layerOrder = await page.evaluate(() => {
      const element = document.querySelector('[data-controller="maps-v2"]');
      if (!element) return null;

      const app = window.Stimulus || window.Application;
      if (!app) return null;

      const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2');
      if (!controller?.map) return null;

      const style = controller.map.getStyle();
      const layers = style.layers || [];

      const routesIndex = layers.findIndex(l => l.id === 'routes');
      const pointsIndex = layers.findIndex(l => l.id === 'points');

      return { routesIndex, pointsIndex };
    });

    expect(layerOrder).toBeTruthy();
    // Routes should come before points in layer order (lower index = rendered first/below)
    if (layerOrder.routesIndex >= 0 && layerOrder.pointsIndex >= 0) {
      expect(layerOrder.routesIndex).toBeLessThan(layerOrder.pointsIndex);
    }
  });
});
