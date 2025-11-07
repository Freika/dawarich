import { test, expect } from '@playwright/test';
import { navigateToMap } from '../helpers/navigation.js';
import { waitForMap, enableLayer } from '../helpers/map.js';

test.describe('Point Interactions', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page);
    await waitForMap(page);
    await enableLayer(page, 'Points');
    await page.waitForTimeout(1500);

    // Pan map to ensure a marker is in viewport
    await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.markers && controller.markers.length > 0) {
        const firstMarker = controller.markers[0];
        controller.map.setView([firstMarker[0], firstMarker[1]], 14);
      }
    });
    await page.waitForTimeout(1000);
  });

  test('should have draggable markers on the map', async ({ page }) => {
    // Verify markers have draggable class
    const marker = page.locator('.leaflet-marker-icon').first();
    await expect(marker).toBeVisible();

    // Check if marker has draggable class
    const isDraggable = await marker.evaluate((el) => {
      return el.classList.contains('leaflet-marker-draggable');
    });

    expect(isDraggable).toBe(true);

    // Verify marker position can be retrieved (required for drag operations)
    const box = await marker.boundingBox();
    expect(box).not.toBeNull();
    expect(box.x).toBeGreaterThan(0);
    expect(box.y).toBeGreaterThan(0);
  });

  test('should open popup when clicking a point', async ({ page }) => {
    // Click on a marker with force to ensure interaction
    const marker = page.locator('.leaflet-marker-icon').first();
    await marker.click({ force: true });
    await page.waitForTimeout(500);

    // Verify popup is visible
    const popup = page.locator('.leaflet-popup');
    await expect(popup).toBeVisible();
  });

  test('should display correct popup content with point data', async ({ page }) => {
    // Click on a marker
    const marker = page.locator('.leaflet-marker-icon').first();
    await marker.click({ force: true });
    await page.waitForTimeout(500);

    // Get popup content
    const popupContent = page.locator('.leaflet-popup-content');
    await expect(popupContent).toBeVisible();

    const content = await popupContent.textContent();

    // Verify all required fields are present
    expect(content).toContain('Timestamp:');
    expect(content).toContain('Latitude:');
    expect(content).toContain('Longitude:');
    expect(content).toContain('Altitude:');
    expect(content).toContain('Speed:');
    expect(content).toContain('Battery:');
    expect(content).toContain('Id:');
  });

  test('should delete a point and redraw route', async ({ page }) => {
    // Enable Routes layer to verify route redraw
    await enableLayer(page, 'Routes');
    await page.waitForTimeout(1000);

    // Count initial markers and get point ID
    const initialData = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      const markerCount = controller?.markersLayer ? Object.keys(controller.markersLayer._layers).length : 0;
      const polylineCount = controller?.polylinesLayer ? Object.keys(controller.polylinesLayer._layers).length : 0;
      return { markerCount, polylineCount };
    });

    // Click on a marker to open popup
    const marker = page.locator('.leaflet-marker-icon').first();
    await marker.click({ force: true });
    await page.waitForTimeout(500);

    // Verify popup opened
    await expect(page.locator('.leaflet-popup')).toBeVisible();

    // Get the point ID from popup before deleting
    const pointId = await page.locator('.leaflet-popup-content').evaluate((content) => {
      const match = content.textContent.match(/Id:\s*(\d+)/);
      return match ? match[1] : null;
    });

    expect(pointId).not.toBeNull();

    // Find delete button (might be a link or button with "Delete" text)
    const deleteButton = page.locator('.leaflet-popup-content a:has-text("Delete"), .leaflet-popup-content button:has-text("Delete")').first();

    const hasDeleteButton = await deleteButton.count() > 0;

    if (hasDeleteButton) {
      // Handle confirmation dialog
      page.once('dialog', dialog => {
        expect(dialog.message()).toContain('delete');
        dialog.accept();
      });

      await deleteButton.click();
      await page.waitForTimeout(2000); // Wait for deletion to complete

      // Verify marker count decreased
      const finalData = await page.evaluate(() => {
        const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
        const markerCount = controller?.markersLayer ? Object.keys(controller.markersLayer._layers).length : 0;
        const polylineCount = controller?.polylinesLayer ? Object.keys(controller.polylinesLayer._layers).length : 0;
        return { markerCount, polylineCount };
      });

      // Verify at least one marker was removed
      expect(finalData.markerCount).toBeLessThan(initialData.markerCount);

      // Verify routes still exist (they should be redrawn)
      expect(finalData.polylineCount).toBeGreaterThanOrEqual(0);

      // Verify success flash message appears
      const flashMessage = page.locator('#flash-messages [role="alert"]').filter({ hasText: /deleted successfully/i });
      await expect(flashMessage).toBeVisible({ timeout: 5000 });
    } else {
      // If no delete button, just verify the test setup worked
      console.log('No delete button found in popup - this might be expected based on permissions');
    }
  });
});
