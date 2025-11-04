const { test, expect } = require('@playwright/test');

test.describe('Bulk Delete Points', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to map page
    await page.goto('/map', {
      waitUntil: 'domcontentloaded',
      timeout: 30000
    });

    // Wait for map to be initialized
    await page.waitForFunction(() => {
      const container = document.querySelector('#map [data-maps-target="container"]');
      return container && container._leaflet_id !== undefined;
    }, { timeout: 10000 });

    // Close onboarding modal if present
    const onboardingModal = page.locator('#getting_started');
    const isModalOpen = await onboardingModal.evaluate((dialog) => dialog.open).catch(() => false);
    if (isModalOpen) {
      await page.locator('#getting_started button.btn-primary').click();
      await page.waitForTimeout(500);
    }

    // Navigate to a date with points (October 13, 2024)
    const startInput = page.locator('input[type="datetime-local"][name="start_at"]');
    await startInput.clear();
    await startInput.fill('2024-10-13T00:00');

    const endInput = page.locator('input[type="datetime-local"][name="end_at"]');
    await endInput.clear();
    await endInput.fill('2024-10-13T23:59');

    // Click the Search button to submit
    await page.click('input[type="submit"][value="Search"]');

    // Wait for page navigation and map reload
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1000);

    // Enable Points layer
    await page.locator('.leaflet-control-layers').hover();
    await page.waitForTimeout(300);

    const pointsCheckbox = page.locator('.leaflet-control-layers-overlays label:has-text("Points") input[type="checkbox"]');
    const isChecked = await pointsCheckbox.isChecked();
    if (!isChecked) {
      await pointsCheckbox.check();
      await page.waitForTimeout(1000);
    }
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
    // Click area selection tool
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Draw a rectangle on the map to select points
    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    // Draw rectangle from top-left to bottom-right
    const startX = bbox.x + bbox.width * 0.3;
    const startY = bbox.y + bbox.height * 0.3;
    const endX = bbox.x + bbox.width * 0.7;
    const endY = bbox.y + bbox.height * 0.7;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
    await page.waitForTimeout(1000);

    // Check that delete button appears
    const deleteButton = page.locator('#delete-selection-button');
    await expect(deleteButton).toBeVisible();

    // Check button has text "Delete Points"
    await expect(deleteButton).toContainText('Delete Points');
  });

  test('should show point count badge on delete button', async ({ page }) => {
    // Click area selection tool
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Draw rectangle
    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    const startX = bbox.x + bbox.width * 0.3;
    const startY = bbox.y + bbox.height * 0.3;
    const endX = bbox.x + bbox.width * 0.7;
    const endY = bbox.y + bbox.height * 0.7;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
    await page.waitForTimeout(1000);

    // Check for badge with count
    const badge = page.locator('#delete-selection-button .badge');
    await expect(badge).toBeVisible();

    // Badge should contain a number
    const badgeText = await badge.textContent();
    expect(parseInt(badgeText)).toBeGreaterThan(0);
  });

  test('should show cancel button alongside delete button', async ({ page }) => {
    // Click area selection tool
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Draw rectangle
    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    const startX = bbox.x + bbox.width * 0.3;
    const startY = bbox.y + bbox.height * 0.3;
    const endX = bbox.x + bbox.width * 0.7;
    const endY = bbox.y + bbox.height * 0.7;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
    await page.waitForTimeout(1000);

    // Check both buttons exist
    const cancelButton = page.locator('#cancel-selection-button');
    const deleteButton = page.locator('#delete-selection-button');

    await expect(cancelButton).toBeVisible();
    await expect(deleteButton).toBeVisible();
    await expect(cancelButton).toContainText('Cancel');
  });

  test('should cancel selection when cancel button is clicked', async ({ page }) => {
    // Click area selection tool and draw rectangle
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    const startX = bbox.x + bbox.width * 0.3;
    const startY = bbox.y + bbox.height * 0.3;
    const endX = bbox.x + bbox.width * 0.7;
    const endY = bbox.y + bbox.height * 0.7;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
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

    // Click area selection tool and draw rectangle
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    const startX = bbox.x + bbox.width * 0.3;
    const startY = bbox.y + bbox.height * 0.3;
    const endX = bbox.x + bbox.width * 0.7;
    const endY = bbox.y + bbox.height * 0.7;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
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

    // Click area selection tool and draw rectangle
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    const startX = bbox.x + bbox.width * 0.3;
    const startY = bbox.y + bbox.height * 0.3;
    const endX = bbox.x + bbox.width * 0.7;
    const endY = bbox.y + bbox.height * 0.7;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
    await page.waitForTimeout(1000);

    // Click delete button
    const deleteButton = page.locator('#delete-selection-button');
    await deleteButton.click();
    await page.waitForTimeout(2000); // Wait for deletion to complete

    // Check for success flash message
    const flashMessage = page.locator('#flash-messages [role="alert"]');
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

    // Perform deletion
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    const startX = bbox.x + bbox.width * 0.4;
    const startY = bbox.y + bbox.height * 0.4;
    const endX = bbox.x + bbox.width * 0.6;
    const endY = bbox.y + bbox.height * 0.6;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
    await page.waitForTimeout(1000);

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

    // Perform deletion
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    const startX = bbox.x + bbox.width * 0.4;
    const startY = bbox.y + bbox.height * 0.4;
    const endX = bbox.x + bbox.width * 0.6;
    const endY = bbox.y + bbox.height * 0.6;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
    await page.waitForTimeout(1000);

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

    // Perform deletion
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    const startX = bbox.x + bbox.width * 0.3;
    const startY = bbox.y + bbox.height * 0.3;
    const endX = bbox.x + bbox.width * 0.7;
    const endY = bbox.y + bbox.height * 0.7;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
    await page.waitForTimeout(1000);

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

    // Perform deletion
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    const mapContainer = page.locator('#map [data-maps-target="container"]');
    const bbox = await mapContainer.boundingBox();

    const startX = bbox.x + bbox.width * 0.3;
    const startY = bbox.y + bbox.height * 0.3;
    const endX = bbox.x + bbox.width * 0.7;
    const endY = bbox.y + bbox.height * 0.7;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY);
    await page.mouse.up();
    await page.waitForTimeout(1000);

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
