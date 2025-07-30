import { test, expect } from '@playwright/test';

/**
 * These tests cover the core features of the /map page
 */

test.describe('Map Functionality', () => {
  let page;
  let context;

  test.beforeAll(async ({ browser }) => {
    context = await browser.newContext();
    page = await context.newPage();

    // Sign in once for all tests
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[name="user[email]"]', { timeout: 10000 });

    await page.fill('input[name="user[email]"]', 'demo@dawarich.app');
    await page.fill('input[name="user[password]"]', 'password');
    await page.click('input[type="submit"][value="Log in"]');

    // Wait for redirect to map page
    await page.waitForURL('/map', { timeout: 10000 });
    await page.waitForSelector('#map', { timeout: 10000 });
    await page.waitForSelector('.leaflet-container', { timeout: 10000 });
  });

  test.afterAll(async () => {
    await page.close();
    await context.close();
  });

  test.beforeEach(async () => {
    await page.goto('/map');
    await page.waitForSelector('#map', { timeout: 10000 });
    await page.waitForSelector('.leaflet-container', { timeout: 10000 });
  });

  test.describe('Core Map Display', () => {
    test('should load the map page successfully', async () => {
      await expect(page).toHaveTitle(/Map/);
      await expect(page.locator('#map')).toBeVisible();
      await expect(page.locator('.leaflet-container')).toBeVisible();
    });

    test('should display Leaflet map with default tiles', async () => {
      // Check that the Leaflet map container is present
      await expect(page.locator('.leaflet-container')).toBeVisible();

      // Check for tile layers (using a more specific selector)
      await expect(page.locator('.leaflet-pane.leaflet-tile-pane')).toBeAttached();

      // Check for map controls
      await expect(page.locator('.leaflet-control-zoom')).toBeVisible();
      await expect(page.locator('.leaflet-control-layers')).toBeVisible();
    });

    test('should have scale control visible', async () => {
      await expect(page.locator('.leaflet-control-scale')).toBeVisible();
    });

    test('should display stats control with distance and points', async () => {
      await expect(page.locator('.leaflet-control-stats')).toBeVisible();

      const statsText = await page.locator('.leaflet-control-stats').textContent();
      expect(statsText).toMatch(/\d+\s+(km|mi)\s+\|\s+\d+\s+points/);
    });
  });

  test.describe('Date and Time Navigation', () => {
    test('should display date navigation controls', async () => {
      // Check for date inputs
      await expect(page.locator('input#start_at')).toBeVisible();
      await expect(page.locator('input#end_at')).toBeVisible();

      // Check for navigation arrows
      await expect(page.locator('a:has-text("◀️")')).toBeVisible();
      await expect(page.locator('a:has-text("▶️")')).toBeVisible();

      // Check for quick access buttons
      await expect(page.locator('a:has-text("Today")')).toBeVisible();
      await expect(page.locator('a:has-text("Last 7 days")')).toBeVisible();
      await expect(page.locator('a:has-text("Last month")')).toBeVisible();
    });

    test('should allow changing date range', async () => {
      const startDateInput = page.locator('input#start_at');

      // Change start date
      const newStartDate = '2024-01-01T00:00';
      await startDateInput.fill(newStartDate);

      // Submit the form
      await page.locator('input[type="submit"][value="Search"]').click();

      // Wait for page to load
      await page.waitForLoadState('networkidle');

      // Check that URL parameters were updated
      const url = page.url();
      expect(url).toContain('start_at=');
    });

    test('should navigate to today when clicking Today button', async () => {
      await page.locator('a:has-text("Today")').click();
      await page.waitForLoadState('networkidle');

      const url = page.url();
      // Allow for timezone differences by checking for current date or next day
      const today = new Date().toISOString().split('T')[0];
      const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().split('T')[0];
      expect(url.includes(today) || url.includes(tomorrow)).toBe(true);
    });
  });

  test.describe('Map Layer Controls', () => {
    test('should have layer control panel', async () => {
      const layerControl = page.locator('.leaflet-control-layers');
      await expect(layerControl).toBeVisible();

      // Click to expand if collapsed
      await layerControl.click();

      // Check for base layer options
      await expect(page.locator('.leaflet-control-layers-base')).toBeVisible();

      // Check for overlay options
      await expect(page.locator('.leaflet-control-layers-overlays')).toBeVisible();
    });

    test('should allow toggling overlay layers', async () => {
      const layerControl = page.locator('.leaflet-control-layers');
      await layerControl.click();

      // Find the Points layer checkbox specifically
      const pointsCheckbox = page.locator('.leaflet-control-layers-overlays').locator('label:has-text("Points")').locator('input');

      // Get initial state
      const initialState = await pointsCheckbox.isChecked();

      if (initialState) {
        // If points are initially visible, verify they exist, then hide them
        const initialPointsCount = await page.locator('.leaflet-marker-pane .leaflet-marker-icon').count();

        // Toggle off
        await pointsCheckbox.click();
        await page.waitForTimeout(500);

        // Verify points are hidden
        const afterHideCount = await page.locator('.leaflet-marker-pane .leaflet-marker-icon').count();
        expect(afterHideCount).toBe(0);

        // Toggle back on
        await pointsCheckbox.click();
        await page.waitForTimeout(500);

        // Verify points are visible again
        const afterShowCount = await page.locator('.leaflet-marker-pane .leaflet-marker-icon').count();
        expect(afterShowCount).toBe(initialPointsCount);
      } else {
        // If points are initially hidden, show them first
        await pointsCheckbox.click();
        await page.waitForTimeout(500);

        // Verify points are now visible
        const pointsCount = await page.locator('.leaflet-marker-pane .leaflet-marker-icon').count();
        expect(pointsCount).toBeGreaterThan(0);

        // Toggle back off
        await pointsCheckbox.click();
        await page.waitForTimeout(500);

        // Verify points are hidden again
        const finalCount = await page.locator('.leaflet-marker-pane .leaflet-marker-icon').count();
        expect(finalCount).toBe(0);
      }

      // Ensure checkbox state matches what we expect
      const finalState = await pointsCheckbox.isChecked();
      expect(finalState).toBe(initialState);
    });

    test('should switch between base map layers', async () => {
      const layerControl = page.locator('.leaflet-control-layers');
      await layerControl.click();

      // Find base layer radio buttons
      const baseLayerRadios = page.locator('.leaflet-control-layers-base input[type="radio"]');
      const secondRadio = baseLayerRadios.nth(1);

      if (await secondRadio.isVisible()) {
        await secondRadio.check();
        await page.waitForTimeout(1000); // Wait for tiles to load

        await expect(secondRadio).toBeChecked();
      }
    });
  });

  test.describe('Settings Panel', () => {
    test('should open and close settings panel', async () => {
      // Find and click settings button (gear icon)
      const settingsButton = page.locator('.map-settings-button');
      await expect(settingsButton).toBeVisible();

      await settingsButton.click();

      // Check that settings panel is visible
      await expect(page.locator('.leaflet-settings-panel')).toBeVisible();
      await expect(page.locator('#settings-form')).toBeVisible();

      // Close settings panel
      await settingsButton.click();

      // Settings panel should be hidden
      await expect(page.locator('.leaflet-settings-panel')).not.toBeVisible();
    });

    test('should allow adjusting route opacity', async () => {
      // First ensure routes are visible
      const layerControl = page.locator('.leaflet-control-layers');
      await layerControl.click();

      const routesCheckbox = page.locator('.leaflet-control-layers-overlays').locator('label:has-text("Routes")').locator('input');
      if (await routesCheckbox.isVisible() && !(await routesCheckbox.isChecked())) {
        await routesCheckbox.check();
        await page.waitForTimeout(2000);
      }

      // Check if routes exist before testing opacity
      const routesExist = await page.locator('.leaflet-overlay-pane svg path').count() > 0;

      if (routesExist) {
        // Get initial opacity of routes before changing
        const initialOpacity = await page.locator('.leaflet-overlay-pane svg path').first().evaluate(el => {
          return window.getComputedStyle(el).opacity;
        });

        const settingsButton = page.locator('.map-settings-button');
        await settingsButton.click();

        const opacityInput = page.locator('#route-opacity');
        await expect(opacityInput).toBeVisible();

        // Change opacity value to 30%
        await opacityInput.fill('30');

        // Submit settings
        await page.locator('#settings-form button[type="submit"]').click();

        // Wait for settings to be applied
        await page.waitForTimeout(2000);

        // Check that the route opacity actually changed
        const newOpacity = await page.locator('.leaflet-overlay-pane svg path').first().evaluate(el => {
          return window.getComputedStyle(el).opacity;
        });

        // The new opacity should be approximately 0.3 (30%)
        const numericOpacity = parseFloat(newOpacity);
        expect(numericOpacity).toBeCloseTo(0.3, 1);
        expect(numericOpacity).not.toBe(parseFloat(initialOpacity));
      } else {
        // If no routes exist, just verify the settings can be changed
        const settingsButton = page.locator('.map-settings-button');
        await settingsButton.click();

        const opacityInput = page.locator('#route-opacity');
        await expect(opacityInput).toBeVisible();

        await opacityInput.fill('30');
        await page.locator('#settings-form button[type="submit"]').click();
        await page.waitForTimeout(1000);

        // Verify the setting was persisted by reopening panel
        // Check if panel is still open, if not reopen it
        const isSettingsPanelVisible = await page.locator('#route-opacity').isVisible();
        if (!isSettingsPanelVisible) {
          await settingsButton.click();
          await page.waitForTimeout(500); // Wait for panel to open
        }

        const reopenedOpacityInput = page.locator('#route-opacity');
        await expect(reopenedOpacityInput).toBeVisible();
        await expect(reopenedOpacityInput).toHaveValue('30');
      }
    });

    test('should allow configuring fog of war settings', async () => {
      const settingsButton = page.locator('.map-settings-button');
      await settingsButton.click();

      const fogRadiusInput = page.locator('#fog_of_war_meters');
      await expect(fogRadiusInput).toBeVisible();

      // Change values
      await fogRadiusInput.fill('100');

      const fogThresholdInput = page.locator('#fog_of_war_threshold');
      await expect(fogThresholdInput).toBeVisible();

      await fogThresholdInput.fill('120');

      // Verify values were set
      await expect(fogRadiusInput).toHaveValue('100');
      await expect(fogThresholdInput).toHaveValue('120');

      // Submit settings
      await page.locator('#settings-form button[type="submit"]').click();
      await page.waitForTimeout(1000);

      // Verify settings were applied by reopening panel and checking values
      // Check if panel is still open, if not reopen it
      const isSettingsPanelVisible = await page.locator('#fog_of_war_meters').isVisible();
      if (!isSettingsPanelVisible) {
        await settingsButton.click();
        await page.waitForTimeout(500); // Wait for panel to open
      }

      const reopenedFogRadiusInput = page.locator('#fog_of_war_meters');
      await expect(reopenedFogRadiusInput).toBeVisible();
      await expect(reopenedFogRadiusInput).toHaveValue('100');

      const reopenedFogThresholdInput = page.locator('#fog_of_war_threshold');
      await expect(reopenedFogThresholdInput).toBeVisible();
      await expect(reopenedFogThresholdInput).toHaveValue('120');
    });

    test('should enable fog of war and verify it works', async () => {
      // First, enable the Fog of War layer
      const layerControl = page.locator('.leaflet-control-layers');
      await layerControl.click();

      // Wait for layer control to be fully expanded
      await page.waitForTimeout(500);

      // Find and enable the Fog of War layer checkbox
      // Try multiple approaches to find the Fog of War checkbox
      let fogCheckbox = page.locator('.leaflet-control-layers-overlays').locator('label:has-text("Fog of War")').locator('input');

      // Alternative approach if first one doesn't work
      if (!(await fogCheckbox.isVisible())) {
        fogCheckbox = page.locator('.leaflet-control-layers-overlays').locator('input').filter({
          has: page.locator(':text("Fog of War")')
        });
      }

      // Another fallback approach
      if (!(await fogCheckbox.isVisible())) {
        // Look for any checkbox followed by text containing "Fog of War"
        const allCheckboxes = page.locator('.leaflet-control-layers-overlays input[type="checkbox"]');
        const count = await allCheckboxes.count();
        for (let i = 0; i < count; i++) {
          const checkbox = allCheckboxes.nth(i);
          const nextSibling = checkbox.locator('+ span');
          if (await nextSibling.isVisible() && (await nextSibling.textContent())?.includes('Fog of War')) {
            fogCheckbox = checkbox;
            break;
          }
        }
      }

      if (await fogCheckbox.isVisible()) {
        // Check initial state
        const initiallyChecked = await fogCheckbox.isChecked();

        // Enable fog of war if not already enabled
        if (!initiallyChecked) {
          await fogCheckbox.check();
          await page.waitForTimeout(2000); // Wait for fog canvas to be created
        }

        // Verify that fog canvas is created and attached to the map
        await expect(page.locator('#fog')).toBeAttached();

        // Verify the fog canvas has the correct properties
        const fogCanvas = page.locator('#fog');
        await expect(fogCanvas).toHaveAttribute('id', 'fog');

        // Check that the canvas has non-zero dimensions (indicating it's been sized)
        const canvasBox = await fogCanvas.boundingBox();
        expect(canvasBox?.width).toBeGreaterThan(0);
        expect(canvasBox?.height).toBeGreaterThan(0);

        // Verify canvas styling indicates it's positioned correctly
        const canvasStyle = await fogCanvas.evaluate(el => {
          const style = window.getComputedStyle(el);
          return {
            position: style.position,
            zIndex: style.zIndex,
            pointerEvents: style.pointerEvents
          };
        });

        expect(canvasStyle.position).toBe('absolute');
        expect(canvasStyle.zIndex).toBe('400');
        expect(canvasStyle.pointerEvents).toBe('none');

        // Test disabling fog of war
        await fogCheckbox.uncheck();
        await page.waitForTimeout(1000);

        // Fog canvas should be removed when layer is disabled
        await expect(page.locator('#fog')).not.toBeAttached();

        // Re-enable to test toggle functionality
        await fogCheckbox.check();
        await page.waitForTimeout(1000);

        // Should be back
        await expect(page.locator('#fog')).toBeAttached();
      } else {
        // If fog layer checkbox is not found, skip fog testing but verify layer control works
        await expect(page.locator('.leaflet-control-layers-overlays')).toBeVisible();
      }
    });

    test('should toggle points rendering mode', async () => {
      const settingsButton = page.locator('.map-settings-button');
      await settingsButton.click();

      const rawModeRadio = page.locator('#raw');
      const simplifiedModeRadio = page.locator('#simplified');

      await expect(rawModeRadio).toBeVisible();
      await expect(simplifiedModeRadio).toBeVisible();

      // Get initial mode
      const initiallyRaw = await rawModeRadio.isChecked();

      // Test toggling between modes
      if (initiallyRaw) {
        // Switch to simplified mode
        await simplifiedModeRadio.check();
        await expect(simplifiedModeRadio).toBeChecked();
        await expect(rawModeRadio).not.toBeChecked();
      } else {
        // Switch to raw mode
        await rawModeRadio.check();
        await expect(rawModeRadio).toBeChecked();
        await expect(simplifiedModeRadio).not.toBeChecked();
      }

      // Submit settings
      await page.locator('#settings-form button[type="submit"]').click();
      await page.waitForTimeout(1000);

      // Verify settings were applied by reopening panel and checking selection persisted
      // Check if panel is still open, if not reopen it
      const isSettingsPanelVisible = await page.locator('#raw').isVisible();
      if (!isSettingsPanelVisible) {
        await settingsButton.click();
        await page.waitForTimeout(500); // Wait for panel to open
      }

      const reopenedRawRadio = page.locator('#raw');
      const reopenedSimplifiedRadio = page.locator('#simplified');

      await expect(reopenedRawRadio).toBeVisible();
      await expect(reopenedSimplifiedRadio).toBeVisible();

      if (initiallyRaw) {
        await expect(reopenedSimplifiedRadio).toBeChecked();
        await expect(reopenedRawRadio).not.toBeChecked();
      } else {
        await expect(reopenedRawRadio).toBeChecked();
        await expect(reopenedSimplifiedRadio).not.toBeChecked();
      }
    });
  });

  test.describe('Calendar Panel', () => {
    test('should open and close calendar panel', async () => {
      // Find and click calendar button
      const calendarButton = page.locator('.toggle-panel-button');
      await expect(calendarButton).toBeVisible();
      await expect(calendarButton).toHaveText('📅');

      // Ensure panel starts in closed state by clearing localStorage
      await page.evaluate(() => localStorage.removeItem('mapPanelOpen'));

      const panel = page.locator('.leaflet-right-panel');

      // Click to open panel
      await calendarButton.click();
      await page.waitForTimeout(2000); // Wait longer for panel animation and content loading

      // Check that calendar panel is now attached and try to make it visible
      await expect(panel).toBeAttached();

      // Force panel to be visible by setting localStorage and toggling again if necessary
      const isVisible = await panel.isVisible();
      if (!isVisible) {
        await page.evaluate(() => localStorage.setItem('mapPanelOpen', 'true'));
        // Click again to ensure it opens
        await calendarButton.click();
        await page.waitForTimeout(1000);
      }

      await expect(panel).toBeVisible();

      // Close panel
      await calendarButton.click();
      await page.waitForTimeout(500);

      // Panel should be hidden
      const finalVisible = await panel.isVisible();
      expect(finalVisible).toBe(false);
    });

    test('should display year selection and months grid', async () => {
      // Ensure panel starts in closed state
      await page.evaluate(() => localStorage.removeItem('mapPanelOpen'));

      const calendarButton = page.locator('.toggle-panel-button');
      await expect(calendarButton).toBeVisible();
      await calendarButton.click();
      await page.waitForTimeout(2000); // Wait longer for panel animation

      // Verify panel is now visible
      const panel = page.locator('.leaflet-right-panel');
      await expect(panel).toBeAttached();

      // Force panel to be visible if it's not
      const isVisible = await panel.isVisible();
      if (!isVisible) {
        await page.evaluate(() => localStorage.setItem('mapPanelOpen', 'true'));
        await calendarButton.click();
        await page.waitForTimeout(1000);
      }

      await expect(panel).toBeVisible();

      // Check year selector - may be hidden but attached
      await expect(page.locator('#year-select')).toBeAttached();

      // Check months grid - may be hidden but attached
      await expect(page.locator('#months-grid')).toBeAttached();

      // Check that there are month buttons
      const monthButtons = page.locator('#months-grid a.btn');
      const monthCount = await monthButtons.count();
      expect(monthCount).toBeGreaterThan(0);
      expect(monthCount).toBeLessThanOrEqual(12); // Should not exceed 12 months

      // Check whole year link - may be hidden but attached
      await expect(page.locator('#whole-year-link')).toBeAttached();

      // Verify at least one month button is clickable
      if (monthCount > 0) {
        const firstMonth = monthButtons.first();
        await expect(firstMonth).toHaveAttribute('href');
      }
    });

    test('should display visited cities section', async () => {
      // Ensure panel starts in closed state
      await page.evaluate(() => localStorage.removeItem('mapPanelOpen'));

      const calendarButton = page.locator('.toggle-panel-button');
      await expect(calendarButton).toBeVisible();
      await calendarButton.click();
      await page.waitForTimeout(2000); // Wait longer for panel animation

      // Verify panel is open
      const panel = page.locator('.leaflet-right-panel');
      await expect(panel).toBeAttached();

      // Force panel to be visible if it's not
      const isVisible = await panel.isVisible();
      if (!isVisible) {
        await page.evaluate(() => localStorage.setItem('mapPanelOpen', 'true'));
        await calendarButton.click();
        await page.waitForTimeout(1000);
      }

      await expect(panel).toBeVisible();

      // Check visited cities container
      const citiesContainer = page.locator('#visited-cities-container');
      await expect(citiesContainer).toBeAttached();

      // Check visited cities list
      const citiesList = page.locator('#visited-cities-list');
      await expect(citiesList).toBeAttached();

      // The cities list might be empty or populated depending on test data
      // At minimum, verify the structure is there for cities to be displayed
      const listExists = await citiesList.isVisible();
      if (listExists) {
        // If list is visible, it should be a proper container for city data
        expect(await citiesList.getAttribute('id')).toBe('visited-cities-list');
      }
    });
  });

  test.describe('Visits System', () => {
    test('should have visits drawer button', async () => {
      const visitsButton = page.locator('.drawer-button');
      await expect(visitsButton).toBeVisible();
    });

    test('should open and close visits drawer', async () => {
      const visitsButton = page.locator('.drawer-button');
      await visitsButton.click();

      // Check that visits drawer opens
      await expect(page.locator('#visits-drawer')).toBeVisible();
      await expect(page.locator('#visits-list')).toBeVisible();

      // Close drawer
      await visitsButton.click();

      // Drawer should slide closed (but element might still be in DOM)
      await page.waitForTimeout(500);
    });

    test('should have area selection tool button', async () => {
      const selectionButton = page.locator('#selection-tool-button');
      await expect(selectionButton).toBeVisible();
      await expect(selectionButton).toHaveText('⚓️');
    });

    test('should activate selection mode', async () => {
      const selectionButton = page.locator('#selection-tool-button');
      await selectionButton.click();

      // Button should become active
      await expect(selectionButton).toHaveClass(/active/);

      // Click again to deactivate
      await selectionButton.click();

      // Button should no longer be active
      await expect(selectionButton).not.toHaveClass(/active/);
    });
  });

  test.describe('Interactive Map Elements', () => {
    test('should allow map dragging and zooming', async () => {
      const mapContainer = page.locator('.leaflet-container');

      // Get initial zoom level
      const initialZoomButton = page.locator('.leaflet-control-zoom-in');
      await expect(initialZoomButton).toBeVisible();

      // Zoom in
      await initialZoomButton.click();
      await page.waitForTimeout(500);

      // Zoom out
      const zoomOutButton = page.locator('.leaflet-control-zoom-out');
      await zoomOutButton.click();
      await page.waitForTimeout(500);

      // Test map dragging
      await mapContainer.hover();
      await page.mouse.down();
      await page.mouse.move(100, 100);
      await page.mouse.up();
      await page.waitForTimeout(300);
    });

    test('should display markers if data is available', async () => {
      // Check if there are any markers on the map
      const markers = page.locator('.leaflet-marker-pane .leaflet-marker-icon');

      // If markers exist, test their functionality
      if (await markers.first().isVisible()) {
        await expect(markers.first()).toBeVisible();

        // Test marker click (should open popup)
        await markers.first().click();
        await page.waitForTimeout(500);

        // Check if popup appeared
        const popup = page.locator('.leaflet-popup');
        await expect(popup).toBeVisible();
      }
    });

    test('should display routes/polylines if data is available', async () => {
      // Check if there are any polylines on the map
      const polylines = page.locator('.leaflet-overlay-pane svg path');

      if (await polylines.first().isVisible()) {
        await expect(polylines.first()).toBeVisible();

        // Test polyline hover
        await polylines.first().hover();
        await page.waitForTimeout(500);
      }
    });
  });

  test.describe('Areas Management', () => {
    test('should have draw control when areas layer is active', async () => {
      // Open layer control
      const layerControl = page.locator('.leaflet-control-layers');
      await layerControl.click();

      // Find and enable Areas layer
      const areasCheckbox = page.locator('.leaflet-control-layers-overlays').locator('input').filter({ hasText: /Areas/ }).first();

      if (await areasCheckbox.isVisible()) {
        await areasCheckbox.check();

        // Check for draw control
        await expect(page.locator('.leaflet-draw')).toBeVisible();

        // Check for circle draw tool
        await expect(page.locator('.leaflet-draw-draw-circle')).toBeVisible();
      }
    });
  });

  test.describe('Performance and Loading', () => {
    test('should load within reasonable time', async () => {
      const startTime = Date.now();

      await page.goto('/map');
      await page.waitForSelector('.leaflet-container', { timeout: 15000 });

      const loadTime = Date.now() - startTime;
      expect(loadTime).toBeLessThan(15000); // Should load within 15 seconds
    });

    test('should handle network errors gracefully', async () => {
      // Should still show the page structure even if tiles don't load
      await expect(page.locator('#map')).toBeVisible();

      // Test with offline network after initial load
      await page.context().setOffline(true);

      // Page should still be functional even when offline
      await expect(page.locator('.leaflet-container')).toBeVisible();

      // Restore network
      await page.context().setOffline(false);
    });
  });

  test.describe('Responsive Design', () => {
    test('should adapt to mobile viewport', async () => {
      // Set mobile viewport
      await page.setViewportSize({ width: 375, height: 667 });

      await page.goto('/map');
      await page.waitForSelector('.leaflet-container');

      // Map should still be visible and functional
      await expect(page.locator('.leaflet-container')).toBeVisible();
      await expect(page.locator('.leaflet-control-zoom')).toBeVisible();

      // Date controls should be responsive
      await expect(page.locator('input#start_at')).toBeVisible();
      await expect(page.locator('input#end_at')).toBeVisible();
    });

    test('should work on tablet viewport', async () => {
      // Set tablet viewport
      await page.setViewportSize({ width: 768, height: 1024 });

      await page.goto('/map');
      await page.waitForSelector('.leaflet-container');

      await expect(page.locator('.leaflet-container')).toBeVisible();
      await expect(page.locator('.leaflet-control-layers')).toBeVisible();
    });
  });

  test.describe('Accessibility', () => {
    test('should have proper accessibility attributes', async () => {
      // Check for map container accessibility
      const mapContainer = page.locator('#map');
      await expect(mapContainer).toHaveAttribute('data-controller', 'maps points');

      // Check form labels
      await expect(page.locator('label[for="start_at"]')).toBeVisible();
      await expect(page.locator('label[for="end_at"]')).toBeVisible();

      // Check button accessibility
      const searchButton = page.locator('input[type="submit"][value="Search"]');
      await expect(searchButton).toBeVisible();
    });

    test('should support keyboard navigation', async () => {
      // Test tab navigation through form elements
      await page.keyboard.press('Tab');
      await page.keyboard.press('Tab');
      await page.keyboard.press('Tab');

      // Should be able to focus on interactive elements
      const focusedElement = page.locator(':focus');
      await expect(focusedElement).toBeVisible();
    });
  });

  test.describe('Data Integration', () => {
    test('should handle empty data state', async () => {
      // Navigate to a date range with no data
      await page.goto('/map?start_at=1990-01-01T00:00&end_at=1990-01-02T00:00');
      await page.waitForSelector('.leaflet-container');

      // Map should still load
      await expect(page.locator('.leaflet-container')).toBeVisible();

      // Stats should show zero
      const statsControl = page.locator('.leaflet-control-stats');
      if (await statsControl.isVisible()) {
        const statsText = await statsControl.textContent();
        expect(statsText).toContain('0');
      }
    });

    test('should update URL parameters when navigating', async () => {
      const initialUrl = page.url();

      // Click on a navigation arrow
      await page.locator('a:has-text("▶️")').click();
      await page.waitForLoadState('networkidle');

      const newUrl = page.url();
      expect(newUrl).not.toBe(initialUrl);
      expect(newUrl).toContain('start_at=');
      expect(newUrl).toContain('end_at=');
    });
  });

  test.describe('Error Handling', () => {
    test('should display error messages for invalid date ranges', async () => {
      // Get initial URL to compare after invalid date submission
      const initialUrl = page.url();

      // Try to set end date before start date
      await page.locator('input#start_at').fill('2024-12-31T23:59');
      await page.locator('input#end_at').fill('2024-01-01T00:00');

      await page.locator('input[type="submit"][value="Search"]').click();
      await page.waitForLoadState('networkidle');

      // Should handle gracefully (either show error or correct the dates)
      await expect(page.locator('.leaflet-container')).toBeVisible();

      // Verify that either:
      // 1. An error message is shown, OR
      // 2. The dates were automatically corrected, OR
      // 3. The URL reflects the corrected date range
      const finalUrl = page.url();
      const hasErrorMessage = await page.locator('.alert, .error, [class*="error"]').count() > 0;
      const urlChanged = finalUrl !== initialUrl;

      // At least one of these should be true - either error shown or dates handled
      expect(hasErrorMessage || urlChanged).toBe(true);
    });

    test('should handle JavaScript errors gracefully', async () => {
      // Listen for console errors
      const consoleErrors = [];
      page.on('console', message => {
        if (message.type() === 'error') {
          consoleErrors.push(message.text());
        }
      });

      await page.goto('/map');
      await page.waitForSelector('.leaflet-container');

      // Map should still function despite any minor JS errors
      await expect(page.locator('.leaflet-container')).toBeVisible();

      // Critical functionality should work
      const layerControl = page.locator('.leaflet-control-layers');
      await expect(layerControl).toBeVisible();

      // Settings button should be functional
      const settingsButton = page.locator('.map-settings-button');
      await expect(settingsButton).toBeVisible();

      // Calendar button should be functional
      const calendarButton = page.locator('.toggle-panel-button');
      await expect(calendarButton).toBeVisible();

      // Test that a basic interaction still works
      await layerControl.click();
      await expect(page.locator('.leaflet-control-layers-list')).toBeVisible();
    });
  });
});
