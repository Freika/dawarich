import { test, expect } from '@playwright/test';
import { navigateToMap } from '../helpers/navigation.js';
import { waitForMap } from '../helpers/map.js';

/**
 * Helper to wait for add visit controller to be fully initialized
 */
async function waitForAddVisitController(page) {
  await page.waitForTimeout(2000); // Wait for controller to connect and attach handlers
}

test.describe('Add Visit Control', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page);
    await waitForMap(page);
    await waitForAddVisitController(page);
  });

  test('should show add visit button control', async ({ page }) => {
    const addVisitButton = page.locator('.add-visit-button');
    await expect(addVisitButton).toBeVisible();
  });

  test('should enable add visit mode when clicked', async ({ page }) => {
    const addVisitButton = page.locator('.add-visit-button');
    await addVisitButton.click();
    await page.waitForTimeout(1000);

    // Verify flash message appears
    const flashMessage = page.locator('#flash-messages [role="alert"]:has-text("Click on the map")');
    await expect(flashMessage).toBeVisible({ timeout: 5000 });

    // Verify cursor changed to crosshair
    const cursor = await page.evaluate(() => {
      const container = document.querySelector('#map [data-maps-target="container"]');
      return container?.style.cursor;
    });
    expect(cursor).toBe('crosshair');

    // Verify button has active state (background color applied)
    const hasActiveStyle = await addVisitButton.evaluate((el) => {
      return el.style.backgroundColor !== '';
    });
    expect(hasActiveStyle).toBe(true);
  });

  test('should open popup form when map is clicked', async ({ page }) => {
    const addVisitButton = page.locator('.add-visit-button');
    await addVisitButton.click();
    await page.waitForTimeout(500);

    // Click on map - use bottom left corner which is less likely to have points
    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();
    await page.mouse.click(bbox.x + bbox.width * 0.2, bbox.y + bbox.height * 0.8);
    await page.waitForTimeout(1000);

    // Verify popup is visible
    const popup = page.locator('.leaflet-popup');
    await expect(popup).toBeVisible({ timeout: 10000 });

    // Verify popup contains the add visit form
    await expect(popup.locator('h3:has-text("Add New Visit")')).toBeVisible();

    // Verify marker appears (📍 emoji with class add-visit-marker)
    const marker = page.locator('.add-visit-marker');
    await expect(marker).toBeVisible();
  });

  test('should display correct form content in popup', async ({ page }) => {
    // Enable mode and click map
    await page.locator('.add-visit-button').click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();
    await page.mouse.click(bbox.x + bbox.width * 0.2, bbox.y + bbox.height * 0.8);
    await page.waitForTimeout(1000);

    // Verify popup content has all required elements
    const popupContent = page.locator('.leaflet-popup-content');
    await expect(popupContent.locator('h3:has-text("Add New Visit")')).toBeVisible();
    await expect(popupContent.locator('input#visit-name')).toBeVisible();
    await expect(popupContent.locator('input#visit-start')).toBeVisible();
    await expect(popupContent.locator('input#visit-end')).toBeVisible();
    await expect(popupContent.locator('button:has-text("Create Visit")')).toBeVisible();
    await expect(popupContent.locator('button:has-text("Cancel")')).toBeVisible();

    // Verify name field has focus
    const nameFieldFocused = await page.evaluate(() => {
      return document.activeElement?.id === 'visit-name';
    });
    expect(nameFieldFocused).toBe(true);

    // Verify start and end time have default values
    const startValue = await page.locator('input#visit-start').inputValue();
    const endValue = await page.locator('input#visit-end').inputValue();
    expect(startValue).toBeTruthy();
    expect(endValue).toBeTruthy();
  });

  test('should hide popup and remove marker when cancel is clicked', async ({ page }) => {
    // Enable mode and click map
    await page.locator('.add-visit-button').click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();
    await page.mouse.click(bbox.x + bbox.width * 0.2, bbox.y + bbox.height * 0.8);
    await page.waitForTimeout(1000);

    // Verify popup and marker exist
    await expect(page.locator('.leaflet-popup')).toBeVisible();
    await expect(page.locator('.add-visit-marker')).toBeVisible();

    // Click cancel button
    await page.locator('#cancel-visit').click();
    await page.waitForTimeout(500);

    // Verify popup is hidden
    const popupVisible = await page.locator('.leaflet-popup').isVisible().catch(() => false);
    expect(popupVisible).toBe(false);

    // Verify marker is removed
    const markerCount = await page.locator('.add-visit-marker').count();
    expect(markerCount).toBe(0);

    // Verify cursor is reset to default
    const cursor = await page.evaluate(() => {
      const container = document.querySelector('#map [data-maps-target="container"]');
      return container?.style.cursor;
    });
    expect(cursor).toBe('');

    // Verify mode was exited (cursor should be reset)
    const cursorReset = await page.evaluate(() => {
      const container = document.querySelector('#map [data-maps-target="container"]');
      return container?.style.cursor === '';
    });
    expect(cursorReset).toBe(true);
  });

  test('should create visit and show marker on map when submitted', async ({ page }) => {
    // Get initial confirmed visit count
    const initialCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.confirmedVisitCircles?._layers) {
        return Object.keys(controller.visitsManager.confirmedVisitCircles._layers).length;
      }
      return 0;
    });

    // Enable mode and click map
    await page.locator('.add-visit-button').click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();
    await page.mouse.click(bbox.x + bbox.width * 0.2, bbox.y + bbox.height * 0.8);
    await page.waitForTimeout(1000);

    // Fill form with unique visit name
    const visitName = `E2E Test Visit ${Date.now()}`;
    await page.locator('#visit-name').fill(visitName);

    // Submit form
    await page.locator('button:has-text("Create Visit")').click();
    await page.waitForTimeout(2000);

    // Verify success message
    const flashMessage = page.locator('#flash-messages [role="alert"]:has-text("created successfully")');
    await expect(flashMessage).toBeVisible({ timeout: 5000 });

    // Verify popup is closed
    const popupVisible = await page.locator('.leaflet-popup').isVisible().catch(() => false);
    expect(popupVisible).toBe(false);

    // Verify confirmed visit marker count increased
    const finalCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.confirmedVisitCircles?._layers) {
        return Object.keys(controller.visitsManager.confirmedVisitCircles._layers).length;
      }
      return 0;
    });

    expect(finalCount).toBeGreaterThan(initialCount);
  });

  test('should disable add visit mode when clicked second time', async ({ page }) => {
    const addVisitButton = page.locator('.add-visit-button');

    // First click - enable mode
    await addVisitButton.click();
    await page.waitForTimeout(500);

    // Verify mode is enabled
    const cursorEnabled = await page.evaluate(() => {
      const container = document.querySelector('#map [data-maps-target="container"]');
      return container?.style.cursor === 'crosshair';
    });
    expect(cursorEnabled).toBe(true);

    // Second click - disable mode
    await addVisitButton.click();
    await page.waitForTimeout(500);

    // Verify cursor is reset
    const cursorDisabled = await page.evaluate(() => {
      const container = document.querySelector('#map [data-maps-target="container"]');
      return container?.style.cursor;
    });
    expect(cursorDisabled).toBe('');

    // Verify mode was exited by checking if we can click map without creating marker
    const isAddingVisit = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'add-visit');
      return controller?.isAddingVisit === true;
    });
    expect(isAddingVisit).toBe(false);
  });

  test('should ensure only one visit popup is open at a time', async ({ page }) => {
    const addVisitButton = page.locator('.add-visit-button');
    await addVisitButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    // Click first location on map
    await page.mouse.click(bbox.x + bbox.width * 0.3, bbox.y + bbox.height * 0.3);
    await page.waitForTimeout(500);

    // Verify first popup exists
    let popupCount = await page.locator('.leaflet-popup').count();
    expect(popupCount).toBe(1);

    // Get the content of first popup to verify it exists
    const firstPopupContent = await page.locator('.leaflet-popup-content input#visit-name').count();
    expect(firstPopupContent).toBe(1);

    // Click second location on map
    await page.mouse.click(bbox.x + bbox.width * 0.7, bbox.y + bbox.height * 0.7);
    await page.waitForTimeout(500);

    // Verify still only one popup exists (old one was closed, new one opened)
    popupCount = await page.locator('.leaflet-popup').count();
    expect(popupCount).toBe(1);

    // Verify the popup contains the add visit form (not some other popup)
    const popupContent = page.locator('.leaflet-popup-content');
    await expect(popupContent.locator('h3:has-text("Add New Visit")')).toBeVisible();
    await expect(popupContent.locator('input#visit-name')).toBeVisible();

    // Verify only one marker exists
    const markerCount = await page.locator('.add-visit-marker').count();
    expect(markerCount).toBe(1);
  });
});
