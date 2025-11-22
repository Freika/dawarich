import { test, expect } from '@playwright/test';
import { navigateToMap, closeOnboardingModal } from '../helpers/navigation.js';
import { waitForMap, enableLayer } from '../helpers/map.js';

test.describe('Map Layers', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page);
  });

  test('should enable Routes layer and display routes', async ({ page }) => {
    // Wait for map to be ready
    await page.waitForFunction(() => {
      const container = document.querySelector('#map [data-maps-target="container"]');
      return container && container._leaflet_id !== undefined;
    }, { timeout: 10000 });

    // Navigate to date with data
    const toggleButton = page.locator('button[data-action*="map-controls#toggle"]');
    const isPanelVisible = await page.locator('[data-map-controls-target="panel"]').isVisible();

    if (!isPanelVisible) {
      await toggleButton.click();
      await page.waitForTimeout(300);
    }

    const startInput = page.locator('input[type="datetime-local"][name="start_at"]');
    await startInput.clear();
    await startInput.fill('2024-10-13T00:00');

    const endInput = page.locator('input[type="datetime-local"][name="end_at"]');
    await endInput.clear();
    await endInput.fill('2024-10-13T23:59');

    await page.click('input[type="submit"][value="Search"]');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Close onboarding modal if present
    await closeOnboardingModal(page);

    // Open layer control and enable Routes
    await page.locator('.leaflet-control-layers').hover();
    await page.waitForTimeout(300);

    const routesCheckbox = page.locator('.leaflet-control-layers-overlays label:has-text("Routes") input[type="checkbox"]');
    const isChecked = await routesCheckbox.isChecked();

    if (!isChecked) {
      await routesCheckbox.check();
      await page.waitForTimeout(1000);
    }

    // Verify routes are visible
    const hasRoutes = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.polylinesLayer && controller.polylinesLayer._layers) {
        return Object.keys(controller.polylinesLayer._layers).length > 0;
      }
      return false;
    });

    expect(hasRoutes).toBe(true);
  });

  test('should enable Heatmap layer and display heatmap', async ({ page }) => {
    await waitForMap(page);
    await enableLayer(page, 'Heatmap');

    const hasHeatmap = await page.locator('.leaflet-heatmap-layer').isVisible();
    expect(hasHeatmap).toBe(true);
  });

  test('should enable Fog of War layer and display fog', async ({ page }) => {
    await waitForMap(page);
    await enableLayer(page, 'Fog of War');

    const hasFog = await page.evaluate(() => {
      const fogCanvas = document.getElementById('fog');
      return fogCanvas && fogCanvas instanceof HTMLCanvasElement;
    });

    expect(hasFog).toBe(true);
  });

  test('should enable Areas layer and display areas', async ({ page }) => {
    await waitForMap(page);

    // Check if there are any points in the map - areas need location data
    const hasPoints = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.pointsLayer?._layers) {
        return Object.keys(controller.pointsLayer._layers).length > 0;
      }
      return false;
    });

    if (!hasPoints) {
      console.log('No points found - skipping areas test');
      return;
    }

    const hasAreasLayer = await page.evaluate(() => {
      const mapElement = document.querySelector('#map');
      const app = window.Stimulus;
      const controller = app?.getControllerForElementAndIdentifier(mapElement, 'maps');
      return controller?.areasLayer !== null && controller?.areasLayer !== undefined;
    });

    expect(hasAreasLayer).toBe(true);
  });

  test('should enable Suggested Visits layer', async ({ page }) => {
    await waitForMap(page);
    // Suggested Visits are now under Visits > Suggested in the tree
    await enableLayer(page, 'Suggested');

    const hasSuggestedVisits = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.visitsManager?.visitCircles !== null &&
        controller?.visitsManager?.visitCircles !== undefined;
    });

    expect(hasSuggestedVisits).toBe(true);
  });

  test('should enable Confirmed Visits layer', async ({ page }) => {
    await waitForMap(page);
    // Confirmed Visits are now under Visits > Confirmed in the tree
    await enableLayer(page, 'Confirmed');

    const hasConfirmedVisits = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.visitsManager?.confirmedVisitCircles !== null &&
        controller?.visitsManager?.confirmedVisitCircles !== undefined;
    });

    expect(hasConfirmedVisits).toBe(true);
  });

  test('should enable Scratch Map layer and display visited countries', async ({ page }) => {
    await waitForMap(page);

    // Check if there are any points - scratch map needs location data
    const hasPoints = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.pointsLayer?._layers) {
        return Object.keys(controller.pointsLayer._layers).length > 0;
      }
      return false;
    });

    if (!hasPoints) {
      console.log('No points found - skipping scratch map test');
      return;
    }

    await enableLayer(page, 'Scratch Map');

    // Wait a bit for the layer to load country borders
    await page.waitForTimeout(2000);

    // Verify scratch layer exists and has been initialized
    const hasScratchLayer = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');

      // Check if scratchLayerManager exists
      if (!controller?.scratchLayerManager) return false;

      // Check if scratch layer was created
      const scratchLayer = controller.scratchLayerManager.getLayer();
      return scratchLayer !== null && scratchLayer !== undefined;
    });

    expect(hasScratchLayer).toBe(true);
  });

  test('should remember enabled layers across page reloads', async ({ page }) => {
    await waitForMap(page);

    // Check if there are any points - needed for this test to be meaningful
    const hasPoints = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.pointsLayer?._layers) {
        return Object.keys(controller.pointsLayer._layers).length > 0;
      }
      return false;
    });

    if (!hasPoints) {
      console.log('No points found - skipping layer persistence test');
      return;
    }

    // Enable multiple layers
    await enableLayer(page, 'Points');
    await enableLayer(page, 'Routes');
    await enableLayer(page, 'Heatmap');
    await page.waitForTimeout(500);

    // Get current layer states
    const getLayerStates = () => page.evaluate(() => {
      const layers = {};
      // Use tree structure selectors
      document.querySelectorAll('.leaflet-layerstree-header-label input[type="checkbox"]').forEach(checkbox => {
        const nameSpan = checkbox.closest('.leaflet-layerstree-header').querySelector('.leaflet-layerstree-header-name');
        if (nameSpan) {
          const label = nameSpan.textContent.trim();
          layers[label] = checkbox.checked;
        }
      });
      return layers;
    });

    const layersBeforeReload = await getLayerStates();

    // Reload the page
    await page.reload();
    await closeOnboardingModal(page);
    await waitForMap(page);
    await page.waitForTimeout(1000); // Wait for layers to restore

    // Get layer states after reload
    const layersAfterReload = await getLayerStates();

    // Verify Points, Routes, and Heatmap are still enabled
    expect(layersAfterReload['Points']).toBe(true);
    expect(layersAfterReload['Routes']).toBe(true);
    expect(layersAfterReload['Heatmap']).toBe(true);

    // Verify layer states match before and after
    expect(layersAfterReload).toEqual(layersBeforeReload);
  });
});
