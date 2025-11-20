import { test, expect } from '@playwright/test';
import { navigateToMap } from '../helpers/navigation.js';
import { waitForMap } from '../helpers/map.js';

test.describe('Selection Tool', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page);
    await waitForMap(page);
  });

  test('should enable selection mode when clicked', async ({ page }) => {
    // Click selection tool button
    const selectionButton = page.locator('#selection-tool-button');
    await expect(selectionButton).toBeVisible();
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Verify selection mode is enabled (flash message appears)
    const flashMessage = page.locator('#flash-messages [role="alert"]:has-text("Selection mode enabled")');
    await expect(flashMessage).toBeVisible({ timeout: 5000 });

    // Verify selection mode is active in controller
    const isSelectionActive = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.visitsManager?.isSelectionActive === true;
    });

    expect(isSelectionActive).toBe(true);

    // Verify button has active class
    const hasActiveClass = await selectionButton.evaluate((el) => {
      return el.classList.contains('active');
    });

    expect(hasActiveClass).toBe(true);

    // Verify map dragging is disabled (required for selection to work)
    const isDraggingDisabled = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return !controller?.map?.dragging?.enabled();
    });

    expect(isDraggingDisabled).toBe(true);
  });

  test('should disable selection mode when clicked second time', async ({ page }) => {
    const selectionButton = page.locator('#selection-tool-button');

    // First click - enable selection mode
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Verify selection mode is enabled
    const isEnabledAfterFirstClick = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.visitsManager?.isSelectionActive === true;
    });

    expect(isEnabledAfterFirstClick).toBe(true);

    // Second click - disable selection mode
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Verify selection mode is disabled
    const isDisabledAfterSecondClick = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.visitsManager?.isSelectionActive === false;
    });

    expect(isDisabledAfterSecondClick).toBe(true);

    // Verify no selection rectangle exists
    const hasSelectionRect = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.visitsManager?.selectionRect !== null;
    });

    expect(hasSelectionRect).toBe(false);

    // Verify button no longer has active class
    const hasActiveClass = await selectionButton.evaluate((el) => {
      return el.classList.contains('active');
    });

    expect(hasActiveClass).toBe(false);

    // Verify map dragging is re-enabled
    const isDraggingEnabled = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.map?.dragging?.enabled();
    });

    expect(isDraggingEnabled).toBe(true);
  });

  test('should show info message about dragging to select area', async ({ page }) => {
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Verify informational flash message about dragging
    const flashMessage = page.locator('#flash-messages [role="alert"]');
    const messageText = await flashMessage.textContent();

    expect(messageText).toContain('Click and drag');
  });

  test('should open side panel when selection is complete', async ({ page }) => {
    // Navigate to a date with known data (October 13, 2024 - same as bulk delete tests)
    const startInput = page.locator('input[type="datetime-local"][name="start_at"]');
    await startInput.clear();
    await startInput.fill('2024-10-15T00:00');

    const endInput = page.locator('input[type="datetime-local"][name="end_at"]');
    await endInput.clear();
    await endInput.fill('2024-10-15T23:59');

    await page.click('input[type="submit"][value="Search"]');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Verify drawer is initially closed
    const drawerInitiallyClosed = await page.evaluate(() => {
      const drawer = document.getElementById('visits-drawer');
      return !drawer?.classList.contains('open');
    });

    expect(drawerInitiallyClosed).toBe(true);

    // Enable selection mode
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Draw a selection rectangle on the map
    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    // Draw rectangle covering most of the map to ensure we select points
    const startX = bbox.x + bbox.width * 0.2;
    const startY = bbox.y + bbox.height * 0.2;
    const endX = bbox.x + bbox.width * 0.8;
    const endY = bbox.y + bbox.height * 0.8;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY, { steps: 10 });
    await page.mouse.up();

    // Wait for drawer to open
    await page.waitForTimeout(2000);

    // Verify drawer is now open
    const drawerOpen = await page.evaluate(() => {
      const drawer = document.getElementById('visits-drawer');
      return drawer?.classList.contains('open');
    });

    expect(drawerOpen).toBe(true);

    // Verify drawer shows either selection data or cancel button (indicates selection is active)
    const hasCancelButton = await page.locator('#cancel-selection-button').isVisible();
    expect(hasCancelButton).toBe(true);
  });
});
