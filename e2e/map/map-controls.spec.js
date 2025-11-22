import { test, expect } from '@playwright/test';
import { navigateToMap, closeOnboardingModal, navigateToDate } from '../helpers/navigation.js';
import { waitForMap, getMapZoom } from '../helpers/map.js';

test.describe('Map Page', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page);
  });

  test('should load map container and display map with controls', async ({ page }) => {
    await expect(page.locator('#map')).toBeVisible();
    await waitForMap(page);

    // Verify zoom controls are present
    await expect(page.locator('.leaflet-control-zoom')).toBeVisible();

    // Verify custom map controls are present (from map_controls.js)
    await expect(page.locator('.add-visit-button')).toBeVisible({ timeout: 10000 });
    await expect(page.locator('.toggle-panel-button')).toBeVisible();
    await expect(page.locator('.drawer-button')).toBeVisible();
    await expect(page.locator('#selection-tool-button')).toBeVisible();
  });

  test('should zoom in when clicking zoom in button', async ({ page }) => {
    await waitForMap(page);

    const initialZoom = await getMapZoom(page);
    await page.locator('.leaflet-control-zoom-in').click();
    await page.waitForTimeout(500);
    const newZoom = await getMapZoom(page);

    expect(newZoom).toBeGreaterThan(initialZoom);
  });

  test('should zoom out when clicking zoom out button', async ({ page }) => {
    await waitForMap(page);

    const initialZoom = await getMapZoom(page);
    await page.locator('.leaflet-control-zoom-out').click();
    await page.waitForTimeout(500);
    const newZoom = await getMapZoom(page);

    expect(newZoom).toBeLessThan(initialZoom);
  });

  test('should switch between map tile layers', async ({ page }) => {
    await waitForMap(page);

    await page.locator('.leaflet-control-layers').hover();
    await page.waitForTimeout(300);

    const getSelectedLayer = () => page.evaluate(() => {
      const radio = document.querySelector('.leaflet-control-layers-base input[type="radio"]:checked');
      return radio ? radio.nextSibling.textContent.trim() : null;
    });

    const initialLayer = await getSelectedLayer();
    await page.locator('.leaflet-control-layers-base input[type="radio"]:not(:checked)').first().click();
    await page.waitForTimeout(500);
    const newLayer = await getSelectedLayer();

    expect(newLayer).not.toBe(initialLayer);
  });

  test('should navigate to specific date and display points layer', async ({ page }) => {
    // Wait for map to be ready
    await page.waitForFunction(() => {
      const container = document.querySelector('#map [data-maps-target="container"]');
      return container && container._leaflet_id !== undefined;
    }, { timeout: 10000 });

    // Navigate to date 13.10.2024
    // First, need to expand the date controls on mobile (if collapsed)
    const toggleButton = page.locator('button[data-action*="map-controls#toggle"]');
    const isPanelVisible = await page.locator('[data-map-controls-target="panel"]').isVisible();

    if (!isPanelVisible) {
      await toggleButton.click();
      await page.waitForTimeout(300);
    }

    // Clear and fill in the start date/time input (midnight)
    const startInput = page.locator('input[type="datetime-local"][name="start_at"]');
    await startInput.clear();
    await startInput.fill('2024-10-13T00:00');

    // Clear and fill in the end date/time input (end of day)
    const endInput = page.locator('input[type="datetime-local"][name="end_at"]');
    await endInput.clear();
    await endInput.fill('2024-10-13T23:59');

    // Click the Search button to submit
    await page.click('input[type="submit"][value="Search"]');

    // Wait for page navigation and map reload
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000); // Wait for map to reinitialize

    // Close onboarding modal if it appears after navigation
    await closeOnboardingModal(page);

    // Open layer control to enable points
    await page.locator('.leaflet-control-layers').hover();
    await page.waitForTimeout(300);

    // Enable points layer if not already enabled
    const pointsCheckbox = page.locator('.leaflet-control-layers-overlays input[type="checkbox"]').first();
    const isChecked = await pointsCheckbox.isChecked();

    if (!isChecked) {
      await pointsCheckbox.check();
      await page.waitForTimeout(1000); // Wait for points to render
    }

    // Verify points are visible on the map
    const layerInfo = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');

      if (!controller) {
        return { error: 'Controller not found' };
      }

      const result = {
        hasMarkersLayer: !!controller.markersLayer,
        markersCount: 0,
        hasPolylinesLayer: !!controller.polylinesLayer,
        polylinesCount: 0,
        hasTracksLayer: !!controller.tracksLayer,
        tracksCount: 0,
      };

      // Check markers layer
      if (controller.markersLayer && controller.markersLayer._layers) {
        result.markersCount = Object.keys(controller.markersLayer._layers).length;
      }

      // Check polylines layer
      if (controller.polylinesLayer && controller.polylinesLayer._layers) {
        result.polylinesCount = Object.keys(controller.polylinesLayer._layers).length;
      }

      // Check tracks layer
      if (controller.tracksLayer && controller.tracksLayer._layers) {
        result.tracksCount = Object.keys(controller.tracksLayer._layers).length;
      }

      return result;
    });

    // Verify that at least one layer has data
    const hasData = layerInfo.markersCount > 0 ||
      layerInfo.polylinesCount > 0 ||
      layerInfo.tracksCount > 0;

    expect(hasData).toBe(true);
  });
});
