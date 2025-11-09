import { test, expect } from '@playwright/test';
import { drawSelectionRectangle } from '../helpers/selection.js';
import { navigateToDate, closeOnboardingModal } from '../helpers/navigation.js';
import { waitForMap, enableLayer } from '../helpers/map.js';

test.describe('Bulk Delete Points', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to map page
    await page.goto('/map', {
      waitUntil: 'domcontentloaded',
      timeout: 30000
    });

    // Wait for map to be initialized
    await waitForMap(page);

    // Close onboarding modal if present
    await closeOnboardingModal(page);

    // Navigate to a date with points (October 13, 2024)
    await navigateToDate(page, '2024-10-13T00:00', '2024-10-13T23:59');

    // Enable Points layer
    await enableLayer(page, 'Points');
  });

  test('should show area selection tool button', async ({ page }) => {
    // Check that area selection button exists
    const selectionButton = page.locator('#selection-tool-button');
    await expect(selectionButton).toBeVisible();
  });

  test('should enable selection mode when area tool is clicked', async ({ page }) => {
    // Click area selection button
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Verify selection mode is active
    const isSelectionActive = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.visitsManager?.selectionMode === true;
    });

    expect(isSelectionActive).toBe(true);
  });

  test('should select points in drawn area and show delete button', async ({ page }) => {
    await drawSelectionRectangle(page);

    // Check that delete button appears
    const deleteButton = page.locator('#delete-selection-button');
    await expect(deleteButton).toBeVisible({ timeout: 10000 });

    // Check button has text "Delete Points"
    await expect(deleteButton).toContainText('Delete Points');
  });

  test('should show point count badge on delete button', async ({ page }) => {
    await drawSelectionRectangle(page);
    await page.waitForTimeout(1000);

    // Check for badge with count
    const badge = page.locator('#delete-selection-button .badge');
    await expect(badge).toBeVisible();

    // Badge should contain a number
    const badgeText = await badge.textContent();
    expect(parseInt(badgeText)).toBeGreaterThan(0);
  });

  test('should show cancel button alongside delete button', async ({ page }) => {
    await drawSelectionRectangle(page);
    await page.waitForTimeout(1000);

    // Check both buttons exist
    const cancelButton = page.locator('#cancel-selection-button');
    const deleteButton = page.locator('#delete-selection-button');

    await expect(cancelButton).toBeVisible();
    await expect(deleteButton).toBeVisible();
    await expect(cancelButton).toContainText('Cancel');
  });

  test('should cancel selection when cancel button is clicked', async ({ page }) => {
    await drawSelectionRectangle(page);
    await page.waitForTimeout(1000);

    // Click cancel button
    const cancelButton = page.locator('#cancel-selection-button');
    await cancelButton.click();
    await page.waitForTimeout(500);

    // Verify buttons are gone
    await expect(cancelButton).not.toBeVisible();
    await expect(page.locator('#delete-selection-button')).not.toBeVisible();

    // Verify selection is cleared
    const isSelectionActive = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.visitsManager?.isSelectionActive === false;
    });

    expect(isSelectionActive).toBe(true);
  });

  test('should show confirmation dialog when delete button is clicked', async ({ page }) => {
    // Set up dialog handler
    let dialogMessage = '';
    page.on('dialog', async dialog => {
      dialogMessage = dialog.message();
      await dialog.dismiss(); // Dismiss to prevent actual deletion
    });

    await drawSelectionRectangle(page);
    await page.waitForTimeout(1000);

    // Click delete button
    const deleteButton = page.locator('#delete-selection-button');
    await deleteButton.click();
    await page.waitForTimeout(500);

    // Verify confirmation dialog appeared with warning
    expect(dialogMessage).toContain('WARNING');
    expect(dialogMessage).toContain('permanently delete');
    expect(dialogMessage).toContain('cannot be undone');
  });

  test('should delete points and show success message when confirmed', async ({ page }) => {
    // Set up dialog handler to accept deletion
    page.on('dialog', async dialog => {
      await dialog.accept();
    });

    // Get initial point count
    const initialPointCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.markers?.length || 0;
    });

    await drawSelectionRectangle(page);
    await page.waitForTimeout(1000);

    // Click delete button
    const deleteButton = page.locator('#delete-selection-button');
    await deleteButton.click();
    await page.waitForTimeout(2000); // Wait for deletion to complete

    // Check for success flash message with specific text
    const flashMessage = page.locator('#flash-messages [role="alert"]:has-text("Successfully deleted")');
    await expect(flashMessage).toBeVisible({ timeout: 5000 });

    const messageText = await flashMessage.textContent();
    expect(messageText).toMatch(/Successfully deleted \d+ point/);

    // Verify point count decreased
    const finalPointCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.markers?.length || 0;
    });

    expect(finalPointCount).toBeLessThan(initialPointCount);
  });

  test('should preserve Routes layer disabled state after deletion', async ({ page }) => {
    // Ensure Routes layer is disabled
    await page.locator('.leaflet-control-layers').hover();
    await page.waitForTimeout(300);

    const routesCheckbox = page.locator('.leaflet-control-layers-overlays label:has-text("Routes") input[type="checkbox"]');
    const isRoutesChecked = await routesCheckbox.isChecked();
    if (isRoutesChecked) {
      await routesCheckbox.uncheck();
      await page.waitForTimeout(500);
    }

    // Set up dialog handler to accept deletion
    page.on('dialog', async dialog => {
      await dialog.accept();
    });

    // Perform deletion using same selection logic as helper
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    // Use larger selection area to ensure we select points
    const startX = bbox.x + bbox.width * 0.2;
    const startY = bbox.y + bbox.height * 0.2;
    const endX = bbox.x + bbox.width * 0.8;
    const endY = bbox.y + bbox.height * 0.8;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY, { steps: 10 });
    await page.mouse.up();
    await page.waitForTimeout(2000);

    // Wait for drawer and button to appear
    await page.waitForSelector('#visits-drawer.open', { timeout: 15000 });
    await page.waitForSelector('#delete-selection-button', { timeout: 15000 });

    const deleteButton = page.locator('#delete-selection-button');
    await deleteButton.click();
    await page.waitForTimeout(2000);

    // Verify Routes layer is still disabled
    const isRoutesLayerVisible = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.map?.hasLayer(controller?.polylinesLayer);
    });

    expect(isRoutesLayerVisible).toBe(false);
  });

  test('should preserve Routes layer enabled state after deletion', async ({ page }) => {
    // Enable Routes layer
    await page.locator('.leaflet-control-layers').hover();
    await page.waitForTimeout(300);

    const routesCheckbox = page.locator('.leaflet-control-layers-overlays label:has-text("Routes") input[type="checkbox"]');
    const isRoutesChecked = await routesCheckbox.isChecked();
    if (!isRoutesChecked) {
      await routesCheckbox.check();
      await page.waitForTimeout(1000);
    }

    // Set up dialog handler to accept deletion
    page.on('dialog', async dialog => {
      await dialog.accept();
    });

    // Perform deletion using same selection logic as helper
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    // Use larger selection area to ensure we select points
    const startX = bbox.x + bbox.width * 0.2;
    const startY = bbox.y + bbox.height * 0.2;
    const endX = bbox.x + bbox.width * 0.8;
    const endY = bbox.y + bbox.height * 0.8;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY, { steps: 10 });
    await page.mouse.up();
    await page.waitForTimeout(2000);

    // Wait for drawer and button to appear
    await page.waitForSelector('#visits-drawer.open', { timeout: 15000 });
    await page.waitForSelector('#delete-selection-button', { timeout: 15000 });

    const deleteButton = page.locator('#delete-selection-button');
    await deleteButton.click();
    await page.waitForTimeout(2000);

    // Verify Routes layer is still enabled
    const isRoutesLayerVisible = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.map?.hasLayer(controller?.polylinesLayer);
    });

    expect(isRoutesLayerVisible).toBe(true);
  });

  test('should update heatmap after bulk deletion', async ({ page }) => {
    // Enable Heatmap layer
    await page.locator('.leaflet-control-layers').hover();
    await page.waitForTimeout(300);

    const heatmapCheckbox = page.locator('.leaflet-control-layers-overlays label:has-text("Heatmap") input[type="checkbox"]');
    const isHeatmapChecked = await heatmapCheckbox.isChecked();
    if (!isHeatmapChecked) {
      await heatmapCheckbox.check();
      await page.waitForTimeout(1000);
    }

    // Get initial heatmap data count
    const initialHeatmapCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.heatmapLayer?._latlngs?.length || 0;
    });

    // Set up dialog handler to accept deletion
    page.on('dialog', async dialog => {
      await dialog.accept();
    });

    // Perform deletion using same selection logic as helper
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    // Use larger selection area to ensure we select points
    const startX = bbox.x + bbox.width * 0.2;
    const startY = bbox.y + bbox.height * 0.2;
    const endX = bbox.x + bbox.width * 0.8;
    const endY = bbox.y + bbox.height * 0.8;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY, { steps: 10 });
    await page.mouse.up();
    await page.waitForTimeout(2000);

    // Wait for drawer and button to appear
    await page.waitForSelector('#visits-drawer.open', { timeout: 15000 });
    await page.waitForSelector('#delete-selection-button', { timeout: 15000 });

    const deleteButton = page.locator('#delete-selection-button');
    await deleteButton.click();
    await page.waitForTimeout(2000);

    // Verify heatmap was updated
    const finalHeatmapCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.heatmapLayer?._latlngs?.length || 0;
    });

    expect(finalHeatmapCount).toBeLessThan(initialHeatmapCount);
  });

  test('should clear selection after successful deletion', async ({ page }) => {
    // Set up dialog handler to accept deletion
    page.on('dialog', async dialog => {
      await dialog.accept();
    });

    // Perform deletion using same selection logic as helper
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    // Use larger selection area to ensure we select points
    const startX = bbox.x + bbox.width * 0.2;
    const startY = bbox.y + bbox.height * 0.2;
    const endX = bbox.x + bbox.width * 0.8;
    const endY = bbox.y + bbox.height * 0.8;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY, { steps: 10 });
    await page.mouse.up();
    await page.waitForTimeout(2000);

    // Wait for drawer and button to appear
    await page.waitForSelector('#visits-drawer.open', { timeout: 15000 });
    await page.waitForSelector('#delete-selection-button', { timeout: 15000 });

    const deleteButton = page.locator('#delete-selection-button');
    await deleteButton.click();
    await page.waitForTimeout(2000);

    // Verify selection is cleared
    const isSelectionActive = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return controller?.visitsManager?.isSelectionActive === false &&
             controller?.visitsManager?.selectedPoints?.length === 0;
    });

    expect(isSelectionActive).toBe(true);

    // Verify buttons are removed
    await expect(page.locator('#cancel-selection-button')).not.toBeVisible();
    await expect(page.locator('#delete-selection-button')).not.toBeVisible();
  });
});
