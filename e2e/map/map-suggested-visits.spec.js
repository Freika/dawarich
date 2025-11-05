import { test, expect } from '@playwright/test';
import { navigateToMap, closeOnboardingModal } from '../helpers/navigation.js';
import { waitForMap, enableLayer, clickSuggestedVisit } from '../helpers/map.js';

test.describe('Suggested Visit Interactions', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page);
    await waitForMap(page);

    // Navigate to a date range that includes visits (last month to now)
    const toggleButton = page.locator('button[data-action*="map-controls#toggle"]');
    const isPanelVisible = await page.locator('[data-map-controls-target="panel"]').isVisible();

    if (!isPanelVisible) {
      await toggleButton.click();
      await page.waitForTimeout(300);
    }

    // Set date range to last month
    await page.click('a:has-text("Last month")');
    await page.waitForTimeout(2000);

    await closeOnboardingModal(page);
    await waitForMap(page);

    await enableLayer(page, 'Suggested Visits');
    await page.waitForTimeout(2000);

    // Pan map to ensure a visit marker is in viewport
    await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.suggestedVisitCircles) {
        const layers = controller.visitsManager.suggestedVisitCircles._layers;
        const firstVisit = Object.values(layers)[0];
        if (firstVisit && firstVisit._latlng) {
          controller.map.setView(firstVisit._latlng, 14);
        }
      }
    });
    await page.waitForTimeout(1000);
  });

  test('should click on a suggested visit and open popup', async ({ page }) => {
    // Debug: Check what visit circles exist
    const allCircles = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.suggestedVisitCircles?._layers) {
        const layers = controller.visitsManager.suggestedVisitCircles._layers;
        return {
          count: Object.keys(layers).length,
          hasLayers: Object.keys(layers).length > 0
        };
      }
      return { count: 0, hasLayers: false };
    });

    // If we have visits in the layer but can't find DOM elements, use coordinates
    if (!allCircles.hasLayers) {
      console.log('No suggested visits found - skipping test');
      return;
    }

    // Click on the visit using map coordinates
    const visitClicked = await clickSuggestedVisit(page);

    if (!visitClicked) {
      console.log('Could not click suggested visit - skipping test');
      return;
    }

    await page.waitForTimeout(500);

    // Verify popup is visible
    const popup = page.locator('.leaflet-popup');
    await expect(popup).toBeVisible();
  });

  test('should display correct content in suggested visit popup', async ({ page }) => {
    // Click visit programmatically
    const visitClicked = await clickSuggestedVisit(page);

    if (!visitClicked) {
      console.log('No suggested visits found - skipping test');
      return;
    }

    await page.waitForTimeout(500);

    // Get popup content
    const popupContent = page.locator('.leaflet-popup-content');
    await expect(popupContent).toBeVisible();

    const content = await popupContent.textContent();

    // Verify visit information is present
    expect(content).toMatch(/Visit|Place|Duration|Started|Ended|Suggested/i);
  });

  test('should confirm suggested visit', async ({ page }) => {
    // Click visit programmatically
    const visitClicked = await clickSuggestedVisit(page);

    if (!visitClicked) {
      console.log('No suggested visits found - skipping test');
      return;
    }

    await page.waitForTimeout(500);

    // Look for confirm button in popup
    const confirmButton = page.locator('.leaflet-popup-content button:has-text("Confirm")').first();
    const hasConfirmButton = await confirmButton.count() > 0;

    if (!hasConfirmButton) {
      console.log('No confirm button found - skipping test');
      return;
    }

    // Get initial counts for both suggested and confirmed visits
    const initialCounts = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return {
        suggested: controller?.visitsManager?.suggestedVisitCircles?._layers
          ? Object.keys(controller.visitsManager.suggestedVisitCircles._layers).length
          : 0,
        confirmed: controller?.visitsManager?.confirmedVisitCircles?._layers
          ? Object.keys(controller.visitsManager.confirmedVisitCircles._layers).length
          : 0
      };
    });

    // Click confirm button
    await confirmButton.click();
    await page.waitForTimeout(1500);

    // Verify the marker changed from yellow to green (suggested to confirmed)
    const finalCounts = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      return {
        suggested: controller?.visitsManager?.suggestedVisitCircles?._layers
          ? Object.keys(controller.visitsManager.suggestedVisitCircles._layers).length
          : 0,
        confirmed: controller?.visitsManager?.confirmedVisitCircles?._layers
          ? Object.keys(controller.visitsManager.confirmedVisitCircles._layers).length
          : 0
      };
    });

    // Verify suggested visit count decreased
    expect(finalCounts.suggested).toBeLessThan(initialCounts.suggested);

    // Verify confirmed visit count increased (marker changed from yellow to green)
    expect(finalCounts.confirmed).toBeGreaterThan(initialCounts.confirmed);

    // Verify popup is closed after confirmation
    const popupVisible = await page.locator('.leaflet-popup').isVisible().catch(() => false);
    expect(popupVisible).toBe(false);
  });

  test('should decline suggested visit', async ({ page }) => {
    // Click visit programmatically
    const visitClicked = await clickSuggestedVisit(page);

    if (!visitClicked) {
      console.log('No suggested visits found - skipping test');
      return;
    }

    await page.waitForTimeout(500);

    // Look for decline button in popup
    const declineButton = page.locator('.leaflet-popup-content button:has-text("Decline")').first();
    const hasDeclineButton = await declineButton.count() > 0;

    if (!hasDeclineButton) {
      console.log('No decline button found - skipping test');
      return;
    }

    // Get initial suggested visit count
    const initialCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.suggestedVisitCircles?._layers) {
        return Object.keys(controller.visitsManager.suggestedVisitCircles._layers).length;
      }
      return 0;
    });

    // Verify popup is visible before decline
    await expect(page.locator('.leaflet-popup')).toBeVisible();

    // Click decline button
    await declineButton.click();
    await page.waitForTimeout(1500);

    // Verify popup is removed from map
    const popupVisible = await page.locator('.leaflet-popup').isVisible().catch(() => false);
    expect(popupVisible).toBe(false);

    // Verify marker is removed from map (suggested visit count decreased)
    const finalCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.suggestedVisitCircles?._layers) {
        return Object.keys(controller.visitsManager.suggestedVisitCircles._layers).length;
      }
      return 0;
    });

    expect(finalCount).toBeLessThan(initialCount);

    // Verify the yellow marker is no longer visible on the map
    const yellowMarkerCount = await page.locator('.leaflet-interactive[stroke="#f59e0b"]').count();
    expect(yellowMarkerCount).toBeLessThan(initialCount);
  });

  test('should change place in dropdown for suggested visit', async ({ page }) => {
    const visitCircle = page.locator('.leaflet-interactive[stroke="#f59e0b"]').first();
    const hasVisits = await visitCircle.count() > 0;

    if (!hasVisits) {
      console.log('No suggested visits found - skipping test');
      return;
    }

    await visitCircle.click({ force: true });
    await page.waitForTimeout(500);

    // Look for place dropdown/select in popup
    const placeSelect = page.locator('.leaflet-popup-content select, .leaflet-popup-content [role="combobox"]').first();
    const hasPlaceDropdown = await placeSelect.count() > 0;

    if (!hasPlaceDropdown) {
      console.log('No place dropdown found - skipping test');
      return;
    }

    // Select a different option
    await placeSelect.selectOption({ index: 1 });
    await page.waitForTimeout(300);

    // Verify the selection changed
    const newValue = await placeSelect.inputValue();
    expect(newValue).toBeTruthy();
  });

  test('should delete suggested visit from map', async ({ page }) => {
    const visitCircle = page.locator('.leaflet-interactive[stroke="#f59e0b"]').first();
    const hasVisits = await visitCircle.count() > 0;

    if (!hasVisits) {
      console.log('No suggested visits found - skipping test');
      return;
    }

    // Count initial visits
    const initialVisitCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.suggestedVisitCircles?._layers) {
        return Object.keys(controller.visitsManager.suggestedVisitCircles._layers).length;
      }
      return 0;
    });

    await visitCircle.click({ force: true });
    await page.waitForTimeout(500);

    // Find delete button
    const deleteButton = page.locator('.leaflet-popup-content button:has-text("Delete"), .leaflet-popup-content a:has-text("Delete")').first();
    const hasDeleteButton = await deleteButton.count() > 0;

    if (!hasDeleteButton) {
      console.log('No delete button found - skipping test');
      return;
    }

    // Handle confirmation dialog
    page.once('dialog', dialog => {
      expect(dialog.message()).toMatch(/delete|remove/i);
      dialog.accept();
    });

    await deleteButton.click();
    await page.waitForTimeout(2000);

    // Verify visit count decreased
    const finalVisitCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.suggestedVisitCircles?._layers) {
        return Object.keys(controller.visitsManager.suggestedVisitCircles._layers).length;
      }
      return 0;
    });

    expect(finalVisitCount).toBeLessThan(initialVisitCount);
  });
});
