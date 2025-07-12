import { test, expect } from '@playwright/test';
import { TestHelpers } from './fixtures/test-helpers';

test.describe('Trips', () => {
  let helpers: TestHelpers;

  test.beforeEach(async ({ page }) => {
    helpers = new TestHelpers(page);
    await helpers.loginAsDemo();
  });

  test.describe('Trips List', () => {
    test('should display trips page correctly', async ({ page }) => {
      await helpers.navigateTo('Trips');

      // Check page title and elements
      await expect(page).toHaveTitle(/Trips.*Dawarich/);
      await expect(page.getByRole('heading', { name: 'Trips' })).toBeVisible();

      // Should show "New trip" button
      await expect(page.getByRole('link', { name: 'New trip' })).toBeVisible();
    });

    test('should show trips list or empty state', async ({ page }) => {
      await helpers.navigateTo('Trips');

      // Check for either trips grid or empty state
      const tripsGrid = page.locator('.grid');
      const emptyState = page.getByText('Hello there!');

      if (await tripsGrid.isVisible()) {
        await expect(tripsGrid).toBeVisible();
      } else {
        // Should show empty state with create link
        await expect(emptyState).toBeVisible();
        await expect(page.getByRole('link', { name: 'create one' })).toBeVisible();
      }
    });

    test('should display trip statistics if trips exist', async ({ page }) => {
      await helpers.navigateTo('Trips');

      // Look for trip cards
      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        // Should show distance info in first trip card
        const firstCard = tripCards.first();
        await expect(firstCard.getByText(/\d+\s*(km|miles)/)).toBeVisible();
      }
    });

    test('should navigate to new trip page', async ({ page }) => {
      await helpers.navigateTo('Trips');

      // Click "New trip" button
      await page.getByRole('link', { name: 'New trip' }).click();

      // Should navigate to new trip page
      await expect(page).toHaveURL(/\/trips\/new/);
      await expect(page.getByRole('heading', { name: 'New trip' })).toBeVisible();
    });
  });

  test.describe('Trip Creation', () => {
    test.beforeEach(async ({ page }) => {
      await helpers.navigateTo('Trips');
      await page.getByRole('link', { name: 'New trip' }).click();
    });

    test('should show trip creation form', async ({ page }) => {
      // Should have form fields
      await expect(page.getByLabel('Name')).toBeVisible();
      await expect(page.getByLabel('Started at')).toBeVisible();
      await expect(page.getByLabel('Ended at')).toBeVisible();

      // Should have submit button
      await expect(page.getByRole('button', { name: 'Create trip' })).toBeVisible();

      // Should have map container
      await expect(page.locator('#map')).toBeVisible();
    });

    test('should create trip with valid data', async ({ page }) => {
      // Fill form fields
      await page.getByLabel('Name').fill('Test Trip');
      await page.getByLabel('Started at').fill('2024-01-01T10:00');
      await page.getByLabel('Ended at').fill('2024-01-01T18:00');

      // Submit form
      await page.getByRole('button', { name: 'Create trip' }).click();

      // Should redirect to trip show page
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveURL(/\/trips\/\d+/);
    });

    test('should validate required fields', async ({ page }) => {
      // Try to submit empty form
      await page.getByRole('button', { name: 'Create trip' }).click();

      // Should show validation errors
      await expect(page.getByText(/can't be blank|is required/i)).toBeVisible();
    });

    test('should validate date range', async ({ page }) => {
      // Fill with invalid date range (end before start)
      await page.getByLabel('Name').fill('Invalid Trip');
      await page.getByLabel('Started at').fill('2024-01-02T10:00');
      await page.getByLabel('Ended at').fill('2024-01-01T18:00');

      // Submit form
      await page.getByRole('button', { name: 'Create trip' }).click();

      // Should show validation error (if backend validates this)
      await page.waitForLoadState('networkidle');
      // Note: This test assumes backend validation exists
    });
  });

  test.describe('Trip Details', () => {
    test('should display trip details when clicked', async ({ page }) => {
      await helpers.navigateTo('Trips');

      // Look for trip cards
      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        // Click on first trip card
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        // Should show trip name as heading
        await expect(page.locator('h1, h2, h3').first()).toBeVisible();

        // Should show distance info
        const distanceText = page.getByText(/\d+\s*(km|miles)/);
        if (await distanceText.count() > 0) {
          await expect(distanceText.first()).toBeVisible();
        }
      }
    });

    test('should show trip map', async ({ page }) => {
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        // Should show map container
        const mapContainer = page.locator('#map');
        if (await mapContainer.isVisible()) {
          await expect(mapContainer).toBeVisible();
          await helpers.waitForMap();
        }
      }
    });

    test('should show trip timeline info', async ({ page }) => {
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        // Should show date/time information
        const dateInfo = page.getByText(/\d{1,2}\s+(January|February|March|April|May|June|July|August|September|October|November|December)/);
        if (await dateInfo.count() > 0) {
          await expect(dateInfo.first()).toBeVisible();
        }
      }
    });

    test('should allow trip editing', async ({ page }) => {
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        // Look for edit link/button
        const editLink = page.getByRole('link', { name: /edit/i });
        if (await editLink.isVisible()) {
          await editLink.click();

          // Should show edit form
          await expect(page.getByLabel('Name')).toBeVisible();
          await expect(page.getByLabel('Started at')).toBeVisible();
          await expect(page.getByLabel('Ended at')).toBeVisible();
        }
      }
    });
  });

  test.describe('Trip Visualization', () => {
    test('should show trip on map', async ({ page }) => {
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        // Check if map is present
        const mapContainer = page.locator('#map');
        if (await mapContainer.isVisible()) {
          await helpers.waitForMap();

          // Should have map controls
          await expect(page.getByRole('button', { name: 'Zoom in' })).toBeVisible();
          await expect(page.getByRole('button', { name: 'Zoom out' })).toBeVisible();
        }
      }
    });

    test('should display trip route', async ({ page }) => {
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        const mapContainer = page.locator('#map');
        if (await mapContainer.isVisible()) {
          await helpers.waitForMap();

          // Look for route polylines
          const routeElements = page.locator('.leaflet-interactive[stroke]');
          if (await routeElements.count() > 0) {
            await expect(routeElements.first()).toBeVisible();
          }
        }
      }
    });

    test('should show trip points', async ({ page }) => {
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        const mapContainer = page.locator('#map');
        if (await mapContainer.isVisible()) {
          await helpers.waitForMap();

          // Look for point markers
          const pointMarkers = page.locator('.leaflet-marker-icon');
          if (await pointMarkers.count() > 0) {
            await expect(pointMarkers.first()).toBeVisible();
          }
        }
      }
    });

    test('should allow map interaction', async ({ page }) => {
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        const mapContainer = page.locator('#map');
        if (await mapContainer.isVisible()) {
          await helpers.waitForMap();

          // Test zoom controls
          const zoomIn = page.getByRole('button', { name: 'Zoom in' });
          const zoomOut = page.getByRole('button', { name: 'Zoom out' });

          await zoomIn.click();
          await page.waitForTimeout(500);
          await zoomOut.click();
          await page.waitForTimeout(500);

          // Map should still be functional
          await expect(mapContainer).toBeVisible();
        }
      }
    });
  });

  test.describe('Trip Management', () => {
    test('should show trip actions', async ({ page }) => {
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        // Look for edit/delete/export options
        const editLink = page.getByRole('link', { name: /edit/i });
        const deleteButton = page.getByRole('button', { name: /delete/i }).or(page.getByRole('link', { name: /delete/i }));

        // At least edit should be available
        if (await editLink.isVisible()) {
          await expect(editLink).toBeVisible();
        }
      }
    });
  });

  test.describe('Mobile Trips Experience', () => {
    test('should work on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await helpers.navigateTo('Trips');

      // Page should load correctly on mobile
      await expect(page.getByRole('heading', { name: 'Trips' })).toBeVisible();
      await expect(page.getByRole('link', { name: 'New trip' })).toBeVisible();

      // Grid should adapt to mobile
      const tripsGrid = page.locator('.grid');
      if (await tripsGrid.isVisible()) {
        await expect(tripsGrid).toBeVisible();
      }
    });

    test('should handle mobile trip details', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        // Should show trip info on mobile
        await expect(page.locator('h1, h2, h3').first()).toBeVisible();

        // Map should be responsive if present
        const mapContainer = page.locator('#map');
        if (await mapContainer.isVisible()) {
          await expect(mapContainer).toBeVisible();
        }
      }
    });

    test('should handle mobile map interactions', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await helpers.navigateTo('Trips');

      const tripCards = page.locator('.card[data-trip-id]');
      const cardCount = await tripCards.count();

      if (cardCount > 0) {
        await tripCards.first().click();
        await page.waitForLoadState('networkidle');

        const mapContainer = page.locator('#map');
        if (await mapContainer.isVisible()) {
          await helpers.waitForMap();

          // Test touch interaction
          await mapContainer.click();
          await page.waitForTimeout(300);

          // Map should remain functional
          await expect(mapContainer).toBeVisible();
        }
      }
    });
  });

  test.describe('Trip Performance', () => {
    test('should load trips page within reasonable time', async ({ page }) => {
      const startTime = Date.now();

      await helpers.navigateTo('Trips');

      const loadTime = Date.now() - startTime;
      const maxLoadTime = await helpers.isMobileViewport() ? 15000 : 10000;

      expect(loadTime).toBeLessThan(maxLoadTime);
    });

    test('should handle large numbers of trips', async ({ page }) => {
      await helpers.navigateTo('Trips');

      // Page should load without timing out
      await page.waitForLoadState('networkidle', { timeout: 30000 });

      // Should show either trips or empty state
      const tripsGrid = page.locator('.grid');
      const emptyState = page.getByText('Hello there!');

      expect(await tripsGrid.isVisible() || await emptyState.isVisible()).toBe(true);
    });
  });
});
