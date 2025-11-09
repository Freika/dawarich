import { test, expect } from '@playwright/test';
import { closeOnboardingModal, navigateToDate } from '../helpers/navigation.js';
import { drawSelectionRectangle } from '../helpers/selection.js';

/**
 * Side Panel (Visits Drawer) Tests
 *
 * Tests for the side panel that displays visits when selection tool is used.
 * The panel can be toggled via the drawer button and shows suggested/confirmed visits
 * with options to confirm, decline, or merge them.
 */

test.describe('Side Panel', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/map');
    await closeOnboardingModal(page);

    // Wait for map to be fully loaded
    await page.waitForSelector('.leaflet-container', { state: 'visible', timeout: 10000 });
    await page.waitForTimeout(2000);

    // Navigate to October 2024 (has demo data)
    await navigateToDate(page, '2024-10-01T00:00', '2024-10-31T23:59');
    await page.waitForTimeout(2000);
  });

  /**
   * Helper function to click the drawer button
   */
  async function clickDrawerButton(page) {
    const drawerButton = page.locator('.drawer-button');
    await expect(drawerButton).toBeVisible({ timeout: 5000 });
    await drawerButton.click();
    await page.waitForTimeout(500); // Wait for drawer animation
  }

  /**
   * Helper function to check if drawer is open
   */
  async function isDrawerOpen(page) {
    const drawer = page.locator('#visits-drawer');
    const exists = await drawer.count() > 0;
    if (!exists) return false;

    const hasOpenClass = await drawer.evaluate(el => el.classList.contains('open'));
    return hasOpenClass;
  }

  /**
   * Helper function to perform selection and wait for visits to load
   * This is a simplified version that doesn't use the shared helper
   * because we need custom waiting logic for the drawer
   */
  async function selectAreaWithVisits(page) {
    // First, enable Suggested Visits layer to ensure visits are loaded
    const layersButton = page.locator('.leaflet-control-layers-toggle');
    await layersButton.click();
    await page.waitForTimeout(500);

    // Enable "Suggested Visits" layer
    const suggestedVisitsCheckbox = page.locator('input[type="checkbox"]').filter({
      has: page.locator(':scope ~ span', { hasText: 'Suggested Visits' })
    });

    const isChecked = await suggestedVisitsCheckbox.isChecked();
    if (!isChecked) {
      await suggestedVisitsCheckbox.check();
      await page.waitForTimeout(1000);
    }

    // Close layers control
    await layersButton.click();
    await page.waitForTimeout(500);

    // Enable selection mode
    const selectionButton = page.locator('#selection-tool-button');
    await selectionButton.click();
    await page.waitForTimeout(500);

    // Get map bounds for drawing selection
    const map = page.locator('.leaflet-container');
    const mapBox = await map.boundingBox();

    // Calculate coordinates for drawing a large selection area
    // Make it much wider to catch visits - use most of the map area
    const startX = mapBox.x + 100;
    const startY = mapBox.y + 100;
    const endX = mapBox.x + mapBox.width - 400; // Leave room for drawer on right
    const endY = mapBox.y + mapBox.height - 100;

    // Draw selection rectangle
    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(endX, endY, { steps: 10 });
    await page.mouse.up();

    // Wait for drawer to be created and opened
    await page.waitForSelector('#visits-drawer.open', { timeout: 10000 });
    await page.waitForTimeout(3000); // Wait longer for visits API response
  }

  test('should open and close drawer panel via button click', async ({ page }) => {
    // Verify drawer is initially closed
    const initiallyOpen = await isDrawerOpen(page);
    expect(initiallyOpen).toBe(false);

    // Click to open
    await clickDrawerButton(page);

    // Verify drawer is now open
    let drawerOpen = await isDrawerOpen(page);
    expect(drawerOpen).toBe(true);

    // Verify drawer content is visible
    const drawerContent = page.locator('#visits-drawer .drawer');
    await expect(drawerContent).toBeVisible();

    // Click to close
    await clickDrawerButton(page);

    // Verify drawer is now closed
    drawerOpen = await isDrawerOpen(page);
    expect(drawerOpen).toBe(false);
  });

  test('should show visits in panel after selection', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Verify drawer is open
    const drawerOpen = await isDrawerOpen(page);
    expect(drawerOpen).toBe(true);

    // Verify visits list container exists
    const visitsList = page.locator('#visits-list');
    await expect(visitsList).toBeVisible();

    // Wait for API response - check if we have visit items or "no visits" message
    await page.waitForTimeout(2000);

    // Check what content is actually shown
    const visitItems = page.locator('.visit-item');
    const visitCount = await visitItems.count();

    const noVisitsMessage = page.locator('#visits-list p.text-gray-500');

    // Either we have visits OR we have a "no visits" message (not "Loading...")
    if (visitCount > 0) {
      // We have visits - verify the title shows count
      const drawerTitle = page.locator('#visits-drawer .drawer h2');
      const titleText = await drawerTitle.textContent();
      expect(titleText).toMatch(/\d+ visits? found/);
    } else {
      // No visits found - verify we show the appropriate message
      // Should NOT still be showing "Loading visits..."
      const messageText = await noVisitsMessage.textContent();
      expect(messageText).not.toContain('Loading visits');
      expect(messageText).toContain('No visits');
    }
  });

  test('should display visit details in panel', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Open the visits collapsible section
    const visitsSection = page.locator('#visits-section-collapse');
    await expect(visitsSection).toBeVisible();

    const visitsSummary = visitsSection.locator('summary');
    await visitsSummary.click();
    await page.waitForTimeout(500);

    // Check if we have any visits
    const visitCount = await page.locator('.visit-item').count();

    if (visitCount === 0) {
      console.log('Test skipped: No visits available in test data');
      test.skip();
      return;
    }

    // Get first visit item
    const firstVisit = page.locator('.visit-item').first();
    await expect(firstVisit).toBeVisible();

    // Verify visit has required information
    const visitName = firstVisit.locator('.font-semibold');
    await expect(visitName).toBeVisible();
    const nameText = await visitName.textContent();
    expect(nameText.length).toBeGreaterThan(0);

    // Verify time information is present
    const timeInfo = firstVisit.locator('.text-sm.text-gray-600');
    await expect(timeInfo).toBeVisible();

    // Check if this is a suggested visit (has confirm/decline buttons)
    const hasSuggestedButtons = (await firstVisit.locator('.confirm-visit').count()) > 0;

    if (hasSuggestedButtons) {
      // For suggested visits, verify action buttons are present
      const confirmButton = firstVisit.locator('.confirm-visit');
      const declineButton = firstVisit.locator('.decline-visit');

      await expect(confirmButton).toBeVisible();
      await expect(declineButton).toBeVisible();
      expect(await confirmButton.textContent()).toBe('Confirm');
      expect(await declineButton.textContent()).toBe('Decline');
    }
  });

  test('should confirm individual suggested visit from panel', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Open the visits collapsible section
    const visitsSection = page.locator('#visits-section-collapse');
    await expect(visitsSection).toBeVisible();

    const visitsSummary = visitsSection.locator('summary');
    await visitsSummary.click();
    await page.waitForTimeout(500);

    // Find a suggested visit (one with confirm/decline buttons)
    const suggestedVisit = page.locator('.visit-item').filter({ has: page.locator('.confirm-visit') }).first();

    // Check if any suggested visits exist
    const suggestedCount = await page.locator('.visit-item').filter({ has: page.locator('.confirm-visit') }).count();

    if (suggestedCount === 0) {
      console.log('Test skipped: No suggested visits available');
      test.skip();
      return;
    }

    await expect(suggestedVisit).toBeVisible();

    // Verify it has the suggested visit styling (dashed border)
    const hasDashedBorder = await suggestedVisit.evaluate(el =>
      el.classList.contains('border-dashed')
    );
    expect(hasDashedBorder).toBe(true);

    // Get initial count of visits
    const initialVisitCount = await page.locator('.visit-item').count();

    // Click confirm button
    const confirmButton = suggestedVisit.locator('.confirm-visit');
    await confirmButton.click();

    // Wait for API call and UI update
    await page.waitForTimeout(2000);

    // Verify flash message appears
    const flashMessage = page.locator('.flash-message');
    await expect(flashMessage).toBeVisible({ timeout: 5000 });

    // The visit should still be in the list but without confirm/decline buttons
    // Or the count might decrease if it was removed from suggested visits
    const finalVisitCount = await page.locator('.visit-item').count();
    expect(finalVisitCount).toBeLessThanOrEqual(initialVisitCount);
  });

  test('should decline individual suggested visit from panel', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Open the visits collapsible section
    const visitsSection = page.locator('#visits-section-collapse');
    await expect(visitsSection).toBeVisible();

    const visitsSummary = visitsSection.locator('summary');
    await visitsSummary.click();
    await page.waitForTimeout(500);

    // Find a suggested visit
    const suggestedVisit = page.locator('.visit-item').filter({ has: page.locator('.decline-visit') }).first();

    const suggestedCount = await page.locator('.visit-item').filter({ has: page.locator('.decline-visit') }).count();

    if (suggestedCount === 0) {
      console.log('Test skipped: No suggested visits available');
      test.skip();
      return;
    }

    await expect(suggestedVisit).toBeVisible();

    // Get initial count
    const initialVisitCount = await page.locator('.visit-item').count();

    // Click decline button
    const declineButton = suggestedVisit.locator('.decline-visit');
    await declineButton.click();

    // Wait for API call and UI update
    await page.waitForTimeout(2000);

    // Verify flash message
    const flashMessage = page.locator('.flash-message');
    await expect(flashMessage).toBeVisible({ timeout: 5000 });

    // Visit should be removed from the list
    const finalVisitCount = await page.locator('.visit-item').count();
    expect(finalVisitCount).toBeLessThan(initialVisitCount);
  });

  test('should show checkboxes on hover for mass selection', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Open the visits collapsible section
    const visitsSection = page.locator('#visits-section-collapse');
    await expect(visitsSection).toBeVisible();

    const visitsSummary = visitsSection.locator('summary');
    await visitsSummary.click();
    await page.waitForTimeout(500);

    // Check if we have any visits
    const visitCount = await page.locator('.visit-item').count();

    if (visitCount === 0) {
      console.log('Test skipped: No visits available in test data');
      test.skip();
      return;
    }

    const firstVisit = page.locator('.visit-item').first();
    await expect(firstVisit).toBeVisible();

    // Initially, checkbox should be hidden
    const checkboxContainer = firstVisit.locator('.visit-checkbox-container');
    let opacity = await checkboxContainer.evaluate(el => el.style.opacity);
    expect(opacity === '0' || opacity === '').toBe(true);

    // Hover over the visit item
    await firstVisit.hover();
    await page.waitForTimeout(300);

    // Checkbox should now be visible
    opacity = await checkboxContainer.evaluate(el => el.style.opacity);
    expect(opacity).toBe('1');

    // Checkbox should be clickable
    const pointerEvents = await checkboxContainer.evaluate(el => el.style.pointerEvents);
    expect(pointerEvents).toBe('auto');
  });

  test('should select multiple visits and show bulk action buttons', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Open the visits collapsible section
    const visitsSection = page.locator('#visits-section-collapse');
    await expect(visitsSection).toBeVisible();

    const visitsSummary = visitsSection.locator('summary');
    await visitsSummary.click();
    await page.waitForTimeout(500);

    // Verify we have at least 2 visits
    const visitCount = await page.locator('.visit-item').count();
    if (visitCount < 2) {
      console.log('Test skipped: Need at least 2 visits');
      test.skip();
      return;
    }

    // Select first visit by hovering and clicking checkbox
    const firstVisit = page.locator('.visit-item').first();
    await firstVisit.hover();
    await page.waitForTimeout(300);

    const firstCheckbox = firstVisit.locator('.visit-checkbox');
    await firstCheckbox.click();
    await page.waitForTimeout(500);

    // Select second visit
    const secondVisit = page.locator('.visit-item').nth(1);
    await secondVisit.hover();
    await page.waitForTimeout(300);

    const secondCheckbox = secondVisit.locator('.visit-checkbox');
    await secondCheckbox.click();
    await page.waitForTimeout(500);

    // Verify bulk action buttons appear
    const bulkActionsContainer = page.locator('.visit-bulk-actions');
    await expect(bulkActionsContainer).toBeVisible();

    // Verify all three action buttons are present
    const mergeButton = bulkActionsContainer.locator('button').filter({ hasText: 'Merge' });
    const confirmButton = bulkActionsContainer.locator('button').filter({ hasText: 'Confirm' });
    const declineButton = bulkActionsContainer.locator('button').filter({ hasText: 'Decline' });

    await expect(mergeButton).toBeVisible();
    await expect(confirmButton).toBeVisible();
    await expect(declineButton).toBeVisible();

    // Verify selection count text
    const selectionText = bulkActionsContainer.locator('.text-sm.text-center');
    const selectionTextContent = await selectionText.textContent();
    expect(selectionTextContent).toContain('2 visits selected');

    // Verify cancel button exists
    const cancelButton = bulkActionsContainer.locator('button').filter({ hasText: 'Cancel Selection' });
    await expect(cancelButton).toBeVisible();
  });

  test('should cancel mass selection', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Open the visits collapsible section
    const visitsSection = page.locator('#visits-section-collapse');
    await expect(visitsSection).toBeVisible();

    const visitsSummary = visitsSection.locator('summary');
    await visitsSummary.click();
    await page.waitForTimeout(500);

    const visitCount = await page.locator('.visit-item').count();
    if (visitCount < 2) {
      console.log('Test skipped: Need at least 2 visits');
      test.skip();
      return;
    }

    // Select two visits
    const firstVisit = page.locator('.visit-item').first();
    await firstVisit.hover();
    await page.waitForTimeout(300);
    await firstVisit.locator('.visit-checkbox').click();
    await page.waitForTimeout(500);

    const secondVisit = page.locator('.visit-item').nth(1);
    await secondVisit.hover();
    await page.waitForTimeout(300);
    await secondVisit.locator('.visit-checkbox').click();
    await page.waitForTimeout(500);

    // Verify bulk actions are visible
    const bulkActions = page.locator('.visit-bulk-actions');
    await expect(bulkActions).toBeVisible();

    // Click cancel button
    const cancelButton = bulkActions.locator('button').filter({ hasText: 'Cancel Selection' });
    await cancelButton.click();
    await page.waitForTimeout(500);

    // Verify bulk actions are removed
    await expect(bulkActions).not.toBeVisible();

    // Verify checkboxes are unchecked
    const checkedCheckboxes = await page.locator('.visit-checkbox:checked').count();
    expect(checkedCheckboxes).toBe(0);
  });

  test('should mass confirm multiple visits', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Open the visits collapsible section
    const visitsSection = page.locator('#visits-section-collapse');
    await expect(visitsSection).toBeVisible();

    const visitsSummary = visitsSection.locator('summary');
    await visitsSummary.click();
    await page.waitForTimeout(500);

    // Find suggested visits (those with confirm buttons)
    const suggestedVisits = page.locator('.visit-item').filter({ has: page.locator('.confirm-visit') });
    const suggestedCount = await suggestedVisits.count();

    if (suggestedCount < 2) {
      console.log('Test skipped: Need at least 2 suggested visits');
      test.skip();
      return;
    }

    // Get initial count
    const initialVisitCount = await page.locator('.visit-item').count();

    // Select first two suggested visits
    const firstSuggested = suggestedVisits.first();
    await firstSuggested.hover();
    await page.waitForTimeout(300);
    await firstSuggested.locator('.visit-checkbox').click();
    await page.waitForTimeout(500);

    const secondSuggested = suggestedVisits.nth(1);
    await secondSuggested.hover();
    await page.waitForTimeout(300);
    await secondSuggested.locator('.visit-checkbox').click();
    await page.waitForTimeout(500);

    // Click mass confirm button
    const bulkActions = page.locator('.visit-bulk-actions');
    const confirmButton = bulkActions.locator('button').filter({ hasText: 'Confirm' });
    await confirmButton.click();

    // Wait for API call
    await page.waitForTimeout(2000);

    // Verify flash message
    const flashMessage = page.locator('.flash-message');
    await expect(flashMessage).toBeVisible({ timeout: 5000 });

    // The visits might be removed or updated in the list
    // At minimum, bulk actions should be removed
    const bulkActionsVisible = await bulkActions.isVisible().catch(() => false);
    expect(bulkActionsVisible).toBe(false);
  });

  test('should mass decline multiple visits', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Open the visits collapsible section
    const visitsSection = page.locator('#visits-section-collapse');
    await expect(visitsSection).toBeVisible();

    const visitsSummary = visitsSection.locator('summary');
    await visitsSummary.click();
    await page.waitForTimeout(500);

    const suggestedVisits = page.locator('.visit-item').filter({ has: page.locator('.decline-visit') });
    const suggestedCount = await suggestedVisits.count();

    if (suggestedCount < 2) {
      console.log('Test skipped: Need at least 2 suggested visits');
      test.skip();
      return;
    }

    // Get initial count
    const initialVisitCount = await page.locator('.visit-item').count();

    // Select two visits
    const firstSuggested = suggestedVisits.first();
    await firstSuggested.hover();
    await page.waitForTimeout(300);
    await firstSuggested.locator('.visit-checkbox').click();
    await page.waitForTimeout(500);

    const secondSuggested = suggestedVisits.nth(1);
    await secondSuggested.hover();
    await page.waitForTimeout(300);
    await secondSuggested.locator('.visit-checkbox').click();
    await page.waitForTimeout(500);

    // Click mass decline button
    const bulkActions = page.locator('.visit-bulk-actions');
    const declineButton = bulkActions.locator('button').filter({ hasText: 'Decline' });
    await declineButton.click();

    // Wait for API call
    await page.waitForTimeout(2000);

    // Verify flash message
    const flashMessage = page.locator('.flash-message');
    await expect(flashMessage).toBeVisible({ timeout: 5000 });

    // Visits should be removed from the list
    const finalVisitCount = await page.locator('.visit-item').count();
    expect(finalVisitCount).toBeLessThan(initialVisitCount);
  });

  test('should mass merge multiple visits', async ({ page }) => {
    await selectAreaWithVisits(page);

    // Open the visits collapsible section
    const visitsSection = page.locator('#visits-section-collapse');
    await expect(visitsSection).toBeVisible();

    const visitsSummary = visitsSection.locator('summary');
    await visitsSummary.click();
    await page.waitForTimeout(500);

    const visitCount = await page.locator('.visit-item').count();
    if (visitCount < 2) {
      console.log('Test skipped: Need at least 2 visits');
      test.skip();
      return;
    }

    // Select two visits
    const firstVisit = page.locator('.visit-item').first();
    await firstVisit.hover();
    await page.waitForTimeout(300);
    await firstVisit.locator('.visit-checkbox').click();
    await page.waitForTimeout(500);

    const secondVisit = page.locator('.visit-item').nth(1);
    await secondVisit.hover();
    await page.waitForTimeout(300);
    await secondVisit.locator('.visit-checkbox').click();
    await page.waitForTimeout(500);

    // Click merge button
    const bulkActions = page.locator('.visit-bulk-actions');
    const mergeButton = bulkActions.locator('button').filter({ hasText: 'Merge' });
    await mergeButton.click();

    // Wait for API call
    await page.waitForTimeout(2000);

    // Verify flash message appears
    const flashMessage = page.locator('.flash-message');
    await expect(flashMessage).toBeVisible({ timeout: 5000 });

    // After merge, the visits should be combined into one
    // So final count should be less than initial
    const finalVisitCount = await page.locator('.visit-item').count();
    expect(finalVisitCount).toBeLessThan(visitCount);
  });

  test('should open and close panel without shifting controls', async ({ page }) => {
    // Get the layer control element
    const layerControl = page.locator('.leaflet-control-layers');
    await expect(layerControl).toBeVisible();

    // Get initial position of the control
    const initialBox = await layerControl.boundingBox();

    // Open the drawer
    await clickDrawerButton(page);
    await page.waitForTimeout(500);

    // Verify drawer is open
    const drawerOpen = await isDrawerOpen(page);
    expect(drawerOpen).toBe(true);

    // Get position after opening - should be the same (no shifting)
    const afterOpenBox = await layerControl.boundingBox();
    expect(afterOpenBox.x).toBe(initialBox.x);
    expect(afterOpenBox.y).toBe(initialBox.y);

    // Close the drawer
    await clickDrawerButton(page);
    await page.waitForTimeout(500);

    // Verify drawer is closed
    const drawerClosed = await isDrawerOpen(page);
    expect(drawerClosed).toBe(false);

    // Get final position - should still be the same
    const afterCloseBox = await layerControl.boundingBox();
    expect(afterCloseBox.x).toBe(initialBox.x);
    expect(afterCloseBox.y).toBe(initialBox.y);
  });
});
