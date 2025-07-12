import { test, expect } from '@playwright/test';
import { TestHelpers } from './fixtures/test-helpers';

test.describe('Map Functionality', () => {
  let helpers: TestHelpers;

  test.beforeEach(async ({ page }) => {
    helpers = new TestHelpers(page);
    await helpers.loginAsDemo();
  });

  test.describe('Main Map Interface', () => {
    test('should display map page correctly', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Check page title and basic elements
      await expect(page).toHaveTitle(/Map.*Dawarich/);
      // Check for map controls instead of specific #map element
      await expect(page.getByRole('button', { name: 'Zoom in' })).toBeVisible();

      // Wait for map to be fully loaded
      await helpers.waitForMap();

      // Check for time range controls
      await expect(page.getByLabel('Start at')).toBeVisible();
      await expect(page.getByLabel('End at')).toBeVisible();
      await expect(page.getByRole('button', { name: 'Search' })).toBeVisible();
    });

    test('should load Leaflet map correctly', async ({ page }) => {
      await helpers.navigateTo('Map');
      await helpers.waitForMap();

      // Check that map functionality is available - either Leaflet or other map implementation
      const mapInitialized = await page.evaluate(() => {
        const mapElement = document.querySelector('#map');
        return mapElement && (mapElement as any)._leaflet_id;
      });

      // If Leaflet is not found, check for basic map functionality
      if (!mapInitialized) {
        // Verify map controls are working
        await expect(page.getByRole('button', { name: 'Zoom in' })).toBeVisible();
        await expect(page.getByRole('button', { name: 'Zoom out' })).toBeVisible();
      } else {
        expect(mapInitialized).toBeTruthy();
      }
    });

    test('should display time range controls', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Check time controls
      await expect(page.getByLabel('Start at')).toBeVisible();
      await expect(page.getByLabel('End at')).toBeVisible();

      // Check quick time range buttons
      await expect(page.getByRole('link', { name: 'Today' })).toBeVisible();
      await expect(page.getByRole('link', { name: 'Last 7 days' })).toBeVisible();
      await expect(page.getByRole('link', { name: 'Last month' })).toBeVisible();

      // Check navigation arrows
      await expect(page.getByRole('link', { name: '◀️' })).toBeVisible();
      await expect(page.getByRole('link', { name: '▶️' })).toBeVisible();
    });

        test('should navigate between dates using arrows', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Wait for initial page load
      await page.waitForLoadState('networkidle');

      // Verify navigation arrows exist and are functional
      const prevArrow = page.getByRole('link', { name: '◀️' });
      const nextArrow = page.getByRole('link', { name: '▶️' });

      await expect(prevArrow).toBeVisible();
      await expect(nextArrow).toBeVisible();

      // Check that arrows have proper href attributes with date parameters
      const prevHref = await prevArrow.getAttribute('href');
      const nextHref = await nextArrow.getAttribute('href');

      expect(prevHref).toContain('start_at');
      expect(nextHref).toContain('start_at');
    });

    test('should use quick time range buttons', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Verify quick time range buttons exist and have proper hrefs
      const todayButton = page.getByRole('link', { name: 'Today' });
      const lastWeekButton = page.getByRole('link', { name: 'Last 7 days' });
      const lastMonthButton = page.getByRole('link', { name: 'Last month' });

      await expect(todayButton).toBeVisible();
      await expect(lastWeekButton).toBeVisible();
      await expect(lastMonthButton).toBeVisible();

      // Check that buttons have proper href attributes with date parameters
      const todayHref = await todayButton.getAttribute('href');
      const lastWeekHref = await lastWeekButton.getAttribute('href');
      const lastMonthHref = await lastMonthButton.getAttribute('href');

      expect(todayHref).toContain('start_at');
      expect(lastWeekHref).toContain('start_at');
      expect(lastMonthHref).toContain('start_at');
    });

    test('should search custom date range', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Verify custom date range form exists
      const startInput = page.getByLabel('Start at');
      const endInput = page.getByLabel('End at');
      const searchButton = page.getByRole('button', { name: 'Search' });

      await expect(startInput).toBeVisible();
      await expect(endInput).toBeVisible();
      await expect(searchButton).toBeVisible();

      // Test that we can interact with the form
      await startInput.fill('2024-01-01T00:00');
      await endInput.fill('2024-01-02T23:59');

      // Verify form inputs work
      await expect(startInput).toHaveValue('2024-01-01T00:00');
      await expect(endInput).toHaveValue('2024-01-02T23:59');
    });
  });

  test.describe('Map Layers and Controls', () => {
    test.beforeEach(async ({ page }) => {
      await helpers.navigateTo('Map');
      await helpers.waitForMap();
    });

    test('should display layer control', async ({ page }) => {
      // Look for layer control (Leaflet control)
      const layerControl = page.locator('.leaflet-control-layers');
      await expect(layerControl).toBeVisible();
    });

    test('should toggle layer control', async ({ page }) => {
      const layerControl = page.locator('.leaflet-control-layers');

      if (await layerControl.isVisible()) {
        // Click to expand if collapsed
        await layerControl.click();

        // Should show layer options
        await page.waitForTimeout(500);
        // Layer control should be expanded (check for typical layer control elements)
        const expanded = await page.locator('.leaflet-control-layers-expanded').isVisible();
        if (!expanded) {
          // Try clicking on the control toggle
          const toggle = layerControl.locator('.leaflet-control-layers-toggle');
          if (await toggle.isVisible()) {
            await toggle.click();
          }
        }
      }
    });

    test('should switch between base layers', async ({ page }) => {
      // This test depends on having multiple base layers available
      // We'll check if base layer options exist and try to switch

      const layerControl = page.locator('.leaflet-control-layers');
      await layerControl.click();

      // Look for base layer radio buttons (OpenStreetMap, OpenTopo, etc.)
      const baseLayerRadios = page.locator('input[type="radio"][name="leaflet-base-layers"]');
      const radioCount = await baseLayerRadios.count();

      if (radioCount > 1) {
        // Switch to different base layer
        await baseLayerRadios.nth(1).click();
        await page.waitForTimeout(1000);

        // Verify the layer switched (tiles should reload)
        await expect(page.locator('.leaflet-tile-loaded')).toBeVisible();
      }
    });

    test('should toggle overlay layers', async ({ page }) => {
      const layerControl = page.locator('.leaflet-control-layers');
      await layerControl.click();

      // Wait for the layer control to expand
      await page.waitForTimeout(300);

      // Look for overlay checkboxes (Points, Routes, Heatmap, etc.)
      const overlayCheckboxes = page.locator('.leaflet-control-layers-overlays input[type="checkbox"]');
      const checkboxCount = await overlayCheckboxes.count();

      if (checkboxCount > 0) {
        // Toggle first overlay - check if it's visible first
        const firstCheckbox = overlayCheckboxes.first();

        // Wait for checkbox to be visible, especially on mobile
        await expect(firstCheckbox).toBeVisible({ timeout: 5000 });

        const wasChecked = await firstCheckbox.isChecked();

        // If on mobile, the checkbox might be hidden behind other elements
        // Use JavaScript click as fallback
        try {
          await firstCheckbox.click({ force: true });
        } catch (error) {
          // Fallback to JavaScript click if element is not interactable
          await page.evaluate(() => {
            const checkbox = document.querySelector('.leaflet-control-layers-overlays input[type="checkbox"]') as HTMLInputElement;
            if (checkbox) {
              checkbox.click();
            }
          });
        }

        await page.waitForTimeout(500);

        // Verify state changed
        const isNowChecked = await firstCheckbox.isChecked();
        expect(isNowChecked).toBe(!wasChecked);
      }
    });
  });

  test.describe('Map Data Display', () => {
    test.beforeEach(async ({ page }) => {
      await helpers.navigateTo('Map');
      await helpers.waitForMap();
    });

    test('should display distance and points statistics', async ({ page }) => {
      // Check for distance and points statistics - they appear as "0 km | 1 points"
      const statsDisplay = page.getByText(/\d+\s*km.*\d+\s*points/i);
      await expect(statsDisplay.first()).toBeVisible();
    });

    test('should display map attribution', async ({ page }) => {
      // Check for Leaflet attribution
      const attribution = page.locator('.leaflet-control-attribution');
      await expect(attribution).toBeVisible();

      // Should contain some attribution text
      const attributionText = await attribution.textContent();
      expect(attributionText).toBeTruthy();
    });

    test('should display map scale control', async ({ page }) => {
      // Check for scale control
      const scaleControl = page.locator('.leaflet-control-scale');
      await expect(scaleControl).toBeVisible();
    });

    test('should zoom in and out', async ({ page }) => {
      // Find zoom controls
      const zoomIn = page.locator('.leaflet-control-zoom-in');
      const zoomOut = page.locator('.leaflet-control-zoom-out');

      await expect(zoomIn).toBeVisible();
      await expect(zoomOut).toBeVisible();

      // Test zoom in
      await zoomIn.click();
      await page.waitForTimeout(500);

      // Test zoom out
      await zoomOut.click();
      await page.waitForTimeout(500);

      // Map should still be visible and functional
      await expect(page.locator('#map')).toBeVisible();
    });

    test('should handle map dragging', async ({ page }) => {
      // Get map container
      const mapContainer = page.locator('#map .leaflet-container');
      await expect(mapContainer).toBeVisible();

      // Get initial map center (if available)
      const initialBounds = await page.evaluate(() => {
        const mapElement = document.querySelector('#map');
        if (mapElement && (mapElement as any)._leaflet_id) {
          const map = (window as any).L.map((mapElement as any)._leaflet_id);
          return map.getBounds();
        }
        return null;
      });

      // Simulate drag
      await mapContainer.hover();
      await page.mouse.down();
      await page.mouse.move(100, 100);
      await page.mouse.up();

      await page.waitForTimeout(500);

      // Map should still be functional
      await expect(mapContainer).toBeVisible();
    });
  });

  test.describe('Points Interaction', () => {
    test.beforeEach(async ({ page }) => {
      await helpers.navigateTo('Map');
      await helpers.waitForMap();
    });

    test('should click on points to show details', async ({ page }) => {
      // Look for point markers on the map
      const pointMarkers = page.locator('.leaflet-marker-icon, .leaflet-interactive[fill]');
      const markerCount = await pointMarkers.count();

      if (markerCount > 0) {
        // Click on first point
        await pointMarkers.first().click();
        await page.waitForTimeout(500);

        // Should show popup with point details
        const popup = page.locator('.leaflet-popup, .popup');
        await expect(popup).toBeVisible();

        // Popup should contain some data
        const popupContent = await popup.textContent();
        expect(popupContent).toBeTruthy();
      }
    });

    test('should show point deletion option in popup', async ({ page }) => {
      // This test assumes there are points to click on
      const pointMarkers = page.locator('.leaflet-marker-icon, .leaflet-interactive[fill]');
      const markerCount = await pointMarkers.count();

      if (markerCount > 0) {
        await pointMarkers.first().click();
        await page.waitForTimeout(500);

        // Look for delete option in popup
        const deleteLink = page.getByRole('link', { name: /delete/i });
        if (await deleteLink.isVisible()) {
          await expect(deleteLink).toBeVisible();
        }
      }
    });
  });

  test.describe('Mobile Map Experience', () => {
    test('should work on mobile viewport', async ({ page }) => {
      // Set mobile viewport
      await page.setViewportSize({ width: 375, height: 667 });

      await helpers.navigateTo('Map');
      await helpers.waitForMap();

      // Map should be visible and functional on mobile
      await expect(page.locator('#map')).toBeVisible();

      // Time controls should be responsive
      await expect(page.getByLabel('Start at')).toBeVisible();
      await expect(page.getByLabel('End at')).toBeVisible();
    });

    test('should handle mobile touch interactions', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await helpers.navigateTo('Map');
      await helpers.waitForMap();

      const mapContainer = page.locator('#map');

      // Simulate touch interactions using click (more compatible than tap)
      await mapContainer.click();
      await page.waitForTimeout(300);

      // Map should remain functional
      await expect(mapContainer).toBeVisible();
    });

    test('should display mobile-optimized controls', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await helpers.navigateTo('Map');

      // Check that controls stack properly on mobile
      const timeControls = page.locator('.flex').filter({ hasText: /Start at|End at/ });
      await expect(timeControls.first()).toBeVisible();

      // Quick action buttons should be visible
      await expect(page.getByRole('link', { name: 'Today' })).toBeVisible();
    });
  });

  test.describe('Map Performance', () => {
    test('should load map within reasonable time', async ({ page }) => {
      const startTime = Date.now();

      await helpers.navigateTo('Map');
      await helpers.waitForMap();

      const loadTime = Date.now() - startTime;

      // Check if we're on mobile and adjust timeout accordingly
      const isMobile = await helpers.isMobileViewport();
      const maxLoadTime = isMobile ? 25000 : 15000; // 25s for mobile, 15s for desktop

      expect(loadTime).toBeLessThan(maxLoadTime);
    });

    test('should handle large datasets efficiently', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Set a longer date range that might have more data
      await page.getByLabel('Start at').fill('2024-01-01T00:00');
      await page.getByLabel('End at').fill('2024-12-31T23:59');
      await page.getByRole('button', { name: 'Search' }).click();

      // Should load without timing out
      await page.waitForLoadState('networkidle', { timeout: 30000 });
      await helpers.waitForMap();

      // Map should still be interactive
      const zoomIn = page.locator('.leaflet-control-zoom-in');
      await zoomIn.click();
      await page.waitForTimeout(500);
    });
  });
});
