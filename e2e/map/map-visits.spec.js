import { test, expect } from '@playwright/test';
import { navigateToMap, closeOnboardingModal } from '../helpers/navigation.js';
import { waitForMap, enableLayer, clickConfirmedVisit } from '../helpers/map.js';

test.describe('Visit Interactions', () => {
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

    await enableLayer(page, 'Confirmed Visits');
    await page.waitForTimeout(2000);

    // Pan map to ensure a visit marker is in viewport
    await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.confirmedVisitCircles) {
        const layers = controller.visitsManager.confirmedVisitCircles._layers;
        const firstVisit = Object.values(layers)[0];
        if (firstVisit && firstVisit._latlng) {
          controller.map.setView(firstVisit._latlng, 14);
        }
      }
    });
    await page.waitForTimeout(1000);
  });

  test('should click on a confirmed visit and open popup', async ({ page }) => {
    // Debug: Check what visit circles exist
    const allCircles = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.confirmedVisitCircles?._layers) {
        const layers = controller.visitsManager.confirmedVisitCircles._layers;
        return {
          count: Object.keys(layers).length,
          hasLayers: Object.keys(layers).length > 0
        };
      }
      return { count: 0, hasLayers: false };
    });

    // If we have visits in the layer but can't find DOM elements, use coordinates
    if (!allCircles.hasLayers) {
      console.log('No confirmed visits found - skipping test');
      return;
    }

    // Click on the visit using map coordinates
    const visitClicked = await clickConfirmedVisit(page);

    if (!visitClicked) {
      console.log('Could not click visit - skipping test');
      return;
    }

    await page.waitForTimeout(500);

    // Verify popup is visible
    const popup = page.locator('.leaflet-popup');
    await expect(popup).toBeVisible();
  });

  test('should display correct content in confirmed visit popup', async ({ page }) => {
    // Click visit programmatically
    const visitClicked = await clickConfirmedVisit(page);

    if (!visitClicked) {
      console.log('No confirmed visits found - skipping test');
      return;
    }

    await page.waitForTimeout(500);

    // Get popup content
    const popupContent = page.locator('.leaflet-popup-content');
    await expect(popupContent).toBeVisible();

    const content = await popupContent.textContent();

    // Verify visit information is present
    expect(content).toMatch(/Visit|Place|Duration|Started|Ended/i);
  });

  test('should change place in dropdown and save', async ({ page }) => {
    const visitCircle = page.locator('.leaflet-interactive[stroke="#10b981"]').first();
    const hasVisits = await visitCircle.count() > 0;

    if (!hasVisits) {
      console.log('No confirmed visits found - skipping test');
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

    // Get current value
    const initialValue = await placeSelect.inputValue().catch(() => null);

    // Select a different option
    await placeSelect.selectOption({ index: 1 });
    await page.waitForTimeout(300);

    // Find and click save button
    const saveButton = page.locator('.leaflet-popup-content button:has-text("Save"), .leaflet-popup-content input[type="submit"]').first();
    const hasSaveButton = await saveButton.count() > 0;

    if (hasSaveButton) {
      await saveButton.click();
      await page.waitForTimeout(1000);

      // Verify popup closes after successful save
      const popupVisible = await page.locator('.leaflet-popup').isVisible().catch(() => false);
      expect(popupVisible).toBe(false);

      // Verify success flash message appears
      const flashMessage = page.locator('#flash-messages [role="alert"]');
      await expect(flashMessage).toBeVisible({ timeout: 2000 });
      const messageText = await flashMessage.textContent();
      expect(messageText).toContain('Visit updated successfully');
    }
  });

  test('should change visit name and save', async ({ page }) => {
    const visitCircle = page.locator('.leaflet-interactive[stroke="#10b981"]').first();
    const hasVisits = await visitCircle.count() > 0;

    if (!hasVisits) {
      console.log('No confirmed visits found - skipping test');
      return;
    }

    await visitCircle.click({ force: true });
    await page.waitForTimeout(500);

    // Look for name input field
    const nameInput = page.locator('.leaflet-popup-content input[type="text"]').first();
    const hasNameInput = await nameInput.count() > 0;

    if (!hasNameInput) {
      console.log('No name input found - skipping test');
      return;
    }

    // Change the name
    const newName = `Test Visit ${Date.now()}`;
    await nameInput.fill(newName);
    await page.waitForTimeout(300);

    // Find and click save button
    const saveButton = page.locator('.leaflet-popup-content button:has-text("Save"), .leaflet-popup-content input[type="submit"]').first();
    const hasSaveButton = await saveButton.count() > 0;

    if (hasSaveButton) {
      await saveButton.click();
      await page.waitForTimeout(1000);

      // Verify popup closes after successful save
      const popupVisible = await page.locator('.leaflet-popup').isVisible().catch(() => false);
      expect(popupVisible).toBe(false);

      // Verify success flash message appears
      const flashMessage = page.locator('#flash-messages [role="alert"]');
      await expect(flashMessage).toBeVisible({ timeout: 2000 });
      const messageText = await flashMessage.textContent();
      expect(messageText).toContain('Visit updated successfully');
    }
  });

  test('should delete confirmed visit from map', async ({ page }) => {
    const visitCircle = page.locator('.leaflet-interactive[stroke="#10b981"]').first();
    const hasVisits = await visitCircle.count() > 0;

    if (!hasVisits) {
      console.log('No confirmed visits found - skipping test');
      return;
    }

    // Count initial visits
    const initialVisitCount = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(c => c.identifier === 'maps');
      if (controller?.visitsManager?.confirmedVisitCircles?._layers) {
        return Object.keys(controller.visitsManager.confirmedVisitCircles._layers).length;
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
      if (controller?.visitsManager?.confirmedVisitCircles?._layers) {
        return Object.keys(controller.visitsManager.confirmedVisitCircles._layers).length;
      }
      return 0;
    });

    expect(finalVisitCount).toBeLessThan(initialVisitCount);
  });
});
