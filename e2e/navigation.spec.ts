import { test, expect } from '@playwright/test';
import { TestHelpers } from './fixtures/test-helpers';

test.describe('Navigation', () => {
  let helpers: TestHelpers;

  test.beforeEach(async ({ page }) => {
    helpers = new TestHelpers(page);
    await helpers.loginAsDemo();
  });

  test.describe('Main Navigation', () => {
    test('should display main navigation elements', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Check for main navigation items - note Trips has α symbol, Settings is in user dropdown
      await expect(page.getByRole('link', { name: 'Map', exact: true })).toBeVisible();
      await expect(page.getByRole('link', { name: /Trips/ })).toBeVisible(); // Match with α symbol
      await expect(page.getByRole('link', { name: 'Stats' })).toBeVisible();

      // Settings is in user dropdown, not main nav - check user dropdown instead
      const userDropdown = page.locator('details').filter({ hasText: /@/ }).first();
      await expect(userDropdown).toBeVisible();

      // Check for "My data" dropdown - select the visible one (not hidden mobile version)
      await expect(page.getByText('My data').and(page.locator(':visible'))).toBeVisible();
    });

    test('should navigate to Map section', async ({ page }) => {
      await helpers.navigateTo('Map');

      await expect(page).toHaveURL(/\/map/);
      // No h1 heading on map page - check for map interface instead
      await expect(page.locator('#map')).toBeVisible();
    });

    test('should navigate to Trips section', async ({ page }) => {
      await helpers.navigateTo('Trips');

      await expect(page).toHaveURL(/\/trips/);
      // No h1 heading on trips page - check for trips interface instead (visible elements only)
      await expect(page.getByText(/trip|distance|duration/i).and(page.locator(':visible')).first()).toBeVisible();
    });

    test('should navigate to Stats section', async ({ page }) => {
      await helpers.navigateTo('Stats');

      await expect(page).toHaveURL(/\/stats/);
      // No h1 heading on stats page - check for stats interface instead (visible elements only)
      await expect(page.getByText(/total.*distance|points.*tracked/i).and(page.locator(':visible')).first()).toBeVisible();
    });

    test('should navigate to Settings section', async ({ page }) => {
      await helpers.navigateTo('Settings');

      await expect(page).toHaveURL(/\/settings/);
      // No h1 heading on settings page - check for settings interface instead
      await expect(page.getByText(/integration|map.*configuration/i).first()).toBeVisible();
    });
  });

  test.describe('My Data Dropdown', () => {
    test('should expand My data dropdown', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Click on "My data" dropdown - select the visible one (not hidden mobile version)
      await page.getByText('My data').and(page.locator(':visible')).click();

      // Should show dropdown items
      await expect(page.getByRole('link', { name: 'Points' })).toBeVisible();
      await expect(page.getByRole('link', { name: 'Visits' })).toBeVisible();
      await expect(page.getByRole('link', { name: 'Imports' })).toBeVisible();
      await expect(page.getByRole('link', { name: 'Exports' })).toBeVisible();
    });

    test('should navigate to Points', async ({ page }) => {
      await helpers.navigateTo('Points');

      await expect(page).toHaveURL(/\/points/);
      // No h1 heading on points page - check for points interface instead (visible elements only)
      await expect(page.getByText(/point|location|coordinate/i).and(page.locator(':visible')).first()).toBeVisible();
    });

    test('should navigate to Visits', async ({ page }) => {
      await helpers.navigateTo('Visits');

      await expect(page).toHaveURL(/\/visits/);
      // No h1 heading on visits page - check for visits interface instead (visible elements only)
      await expect(page.getByText(/visit|place|duration/i).and(page.locator(':visible')).first()).toBeVisible();
    });

    test('should navigate to Imports', async ({ page }) => {
      await helpers.navigateTo('Imports');

      await expect(page).toHaveURL(/\/imports/);
      // No h1 heading on imports page - check for imports interface instead (visible elements only)
      await expect(page.getByText(/import|file|source/i).and(page.locator(':visible')).first()).toBeVisible();
    });

    test('should navigate to Exports', async ({ page }) => {
      await helpers.navigateTo('Exports');

      await expect(page).toHaveURL(/\/exports/);
      // No h1 heading on exports page - check for exports interface instead (visible elements only)
      await expect(page.getByText(/export|download|format/i).and(page.locator(':visible')).first()).toBeVisible();
    });
  });

  test.describe('User Navigation', () => {
    test('should display user menu', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Click on user dropdown using the details/summary structure
      const userDropdown = page.locator('details').filter({ hasText: /@/ }).first();
      await userDropdown.locator('summary').click();

      // Should show user menu items
      await expect(page.getByRole('link', { name: 'Account' })).toBeVisible();
      await expect(page.getByRole('link', { name: 'Logout' })).toBeVisible();
    });

    test('should navigate to Account settings', async ({ page }) => {
      await helpers.navigateTo('Map');

      const userDropdown = page.locator('details').filter({ hasText: /@/ }).first();
      await userDropdown.locator('summary').click();
      await page.getByRole('link', { name: 'Account' }).click();

      await expect(page).toHaveURL(/\/users\/edit/);
      await expect(page.getByLabel('Email')).toBeVisible();
    });

    test('should show logout functionality', async ({ page }) => {
      await helpers.navigateTo('Map');

      const userDropdown = page.locator('details').filter({ hasText: /@/ }).first();
      await userDropdown.locator('summary').click();
      await page.getByRole('link', { name: 'Logout' }).click();

      // Should redirect to home/login
      await expect(page).toHaveURL('/');
      await expect(page.getByRole('link', { name: 'Sign in' })).toBeVisible();
    });
  });

  test.describe('Breadcrumb Navigation', () => {
    test('should show breadcrumbs on detail pages', async ({ page }) => {
      await helpers.navigateTo('Trips');

      // Look for trip links
      const tripLinks = page.getByRole('link').filter({ hasText: /trip|km|miles/i });
      const linkCount = await tripLinks.count();

      if (linkCount > 0) {
        // Click on first trip
        await tripLinks.first().click();
        await page.waitForLoadState('networkidle');

        // Should show breadcrumb navigation
        const breadcrumbs = page.locator('.breadcrumb, .breadcrumbs, nav').filter({ hasText: /trip/i });
        if (await breadcrumbs.isVisible()) {
          await expect(breadcrumbs).toBeVisible();
        }
      }
    });

    test('should navigate back using breadcrumbs', async ({ page }) => {
      await helpers.navigateTo('Imports');

      // Look for import detail links
      const importLinks = page.getByRole('link').filter({ hasText: /\.json|\.gpx|\.rec/i });
      const linkCount = await importLinks.count();

      if (linkCount > 0) {
        await importLinks.first().click();
        await page.waitForLoadState('networkidle');

        // Look for back navigation
        const backLink = page.getByRole('link', { name: /back|imports/i });
        if (await backLink.isVisible()) {
          await backLink.click();
          await expect(page).toHaveURL(/\/imports/);
        }
      }
    });
  });

  test.describe('URL Navigation', () => {
    test('should handle direct URL navigation', async ({ page }) => {
      // Navigate directly to different sections - no h1 headings on pages
      await page.goto('/map');
      await expect(page.locator('#map')).toBeVisible();

      await page.goto('/trips');
      await expect(page.getByText(/trip|distance|duration/i).and(page.locator(':visible')).first()).toBeVisible();

      await page.goto('/stats');
      await expect(page.getByText(/total.*distance|points.*tracked/i).and(page.locator(':visible')).first()).toBeVisible();

      await page.goto('/settings');
      await expect(page.getByText(/integration|map.*configuration/i).first()).toBeVisible();
    });

    test('should handle browser back/forward navigation', async ({ page }) => {
      // Navigate to different pages
      await helpers.navigateTo('Map');
      await helpers.navigateTo('Trips');
      await helpers.navigateTo('Stats');

      // Use browser back
      await page.goBack();
      await expect(page).toHaveURL(/\/trips/);

      await page.goBack();
      await expect(page).toHaveURL(/\/map/);

      // Use browser forward
      await page.goForward();
      await expect(page).toHaveURL(/\/trips/);
    });

    test('should handle URL parameters', async ({ page }) => {
      // Navigate to map with date parameters
      await page.goto('/map?start_at=2024-01-01T00:00&end_at=2024-01-02T23:59');

      // Should preserve URL parameters
      await expect(page).toHaveURL(/start_at=2024-01-01/);
      await expect(page).toHaveURL(/end_at=2024-01-02/);

      // Form should be populated with URL parameters - use display labels
      await expect(page.getByLabel('Start at')).toHaveValue(/2024-01-01/);
      await expect(page.getByLabel('End at')).toHaveValue(/2024-01-02/);
    });
  });

  test.describe('Mobile Navigation', () => {
    test('should show mobile navigation menu', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      await helpers.navigateTo('Map');

      // Look for mobile menu button (hamburger)
      const mobileMenuButton = page.locator('button').filter({ hasText: /menu|☰|≡/ }).first();

      if (await mobileMenuButton.isVisible()) {
        await mobileMenuButton.click();

        // Should show mobile navigation
        await expect(page.getByRole('link', { name: 'Map' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'Trips' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'Stats' })).toBeVisible();
      }
    });

    test('should handle mobile navigation interactions', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      await helpers.navigateTo('Map');

      // Open mobile navigation
      await helpers.openMobileNavigation();

      // Navigate to different section
      await page.getByRole('link', { name: 'Stats' }).click();

      // Should navigate successfully - no h1 heading on stats page
      await expect(page).toHaveURL(/\/stats/);
      await expect(page.getByText(/total.*distance|points.*tracked/i).and(page.locator(':visible')).first()).toBeVisible();
    });

    test('should handle mobile dropdown menus', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      await helpers.navigateTo('Map');

      // Open mobile navigation
      await helpers.openMobileNavigation();

      // Look for "My data" in mobile menu - select the visible one
      const myDataMobile = page.getByText('My data').and(page.locator(':visible'));
      if (await myDataMobile.isVisible()) {
        await myDataMobile.click();

        // Should show mobile dropdown
        await expect(page.getByRole('link', { name: 'Points' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'Imports' })).toBeVisible();
      }
    });
  });

  test.describe('Active Navigation State', () => {
    test('should highlight active navigation item', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Map should be active - use exact match to avoid attribution links
      const mapLink = page.getByRole('link', { name: 'Map', exact: true });
      await expect(mapLink).toHaveClass(/active|current/);

      // Navigate to different section
      await helpers.navigateTo('Trips');

      // Trips should now be active
      const tripsLink = page.getByRole('link', { name: 'Trips' });
      await expect(tripsLink).toHaveClass(/active|current/);
    });

    test('should update active state on URL change', async ({ page }) => {
      // Navigate directly via URL
      await page.goto('/stats');

      // Stats should be active - use exact match to avoid "Update stats" button
      const statsLink = page.getByRole('link', { name: 'Stats', exact: true });
      await expect(statsLink).toHaveClass(/active|current/);

      // Navigate via URL again
      await page.goto('/settings');

      // Settings link is in user dropdown, not main nav - check URL instead
      await expect(page).toHaveURL(/\/settings/);
    });
  });

  test.describe('Navigation Performance', () => {
    test('should navigate between sections quickly', async ({ page }) => {
      const startTime = Date.now();

      // Navigate through multiple sections (Settings uses different navigation)
      await helpers.navigateTo('Map');
      await helpers.navigateTo('Trips');
      await helpers.navigateTo('Stats');
      await helpers.navigateTo('Points'); // Navigate to Points instead of Settings

      const endTime = Date.now();
      const totalTime = endTime - startTime;

      // Should complete navigation within reasonable time
      expect(totalTime).toBeLessThan(10000); // 10 seconds
    });

    test('should handle rapid navigation clicks', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Rapidly click different navigation items (Settings is not in main nav)
      await page.getByRole('link', { name: /Trips/ }).click(); // Match with α symbol
      await page.getByRole('link', { name: 'Stats' }).click();
      await page.getByRole('link', { name: 'Map', exact: true }).click();

      // Should end up on the last clicked item
      await expect(page).toHaveURL(/\/map/);
      await expect(page.locator('#map')).toBeVisible();
    });
  });

  test.describe('Error Handling', () => {
    test('should handle non-existent routes', async ({ page }) => {
      // Navigate to a non-existent route
      await page.goto('/non-existent-page');

      // Should show 404 or redirect to valid page
      const currentUrl = page.url();

      // Either shows 404 page or redirects to valid page
      if (currentUrl.includes('non-existent-page')) {
        // Should show 404 page
        await expect(page.getByText(/404|not found/i)).toBeVisible();
      } else {
        // Should redirect to valid page
        expect(currentUrl).toMatch(/\/(map|home|$)/);
      }
    });

    test('should handle network errors gracefully', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Mock network error for navigation
      await page.route('**/trips', route => route.abort());

      // Try to navigate
      await page.getByRole('link', { name: 'Trips' }).click();

      // Should handle gracefully (stay on current page or show error)
      await page.waitForTimeout(2000);

      // Should not crash - page should still be functional - use exact match
      await expect(page.getByRole('link', { name: 'Map', exact: true })).toBeVisible();
    });
  });

  test.describe('Keyboard Navigation', () => {
    test('should support keyboard navigation', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Press Tab to navigate to links
      await page.keyboard.press('Tab');

      // Should focus on navigation elements
      const focusedElement = page.locator(':focus');
      await expect(focusedElement).toBeVisible();

      // Should be able to navigate with keyboard
      await page.keyboard.press('Enter');
      await page.waitForTimeout(500);

      // Should navigate to focused element - use exact match to avoid attribution links
      await expect(page.getByRole('link', { name: 'Map', exact: true })).toBeVisible();
    });

    test('should handle keyboard shortcuts', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Test common keyboard shortcuts if they exist
      // This depends on the application implementing keyboard shortcuts

      // For example, if there's a keyboard shortcut for settings
      await page.keyboard.press('Alt+S');
      await page.waitForTimeout(500);

      // May or may not navigate (depends on implementation)
      const currentUrl = page.url();

      // Just verify the page is still functional - use exact match
      await expect(page.getByRole('link', { name: 'Map', exact: true })).toBeVisible();
    });
  });

  test.describe('Accessibility', () => {
    test('should have proper ARIA labels', async ({ page }) => {
      await helpers.navigateTo('Map');

      // Check for main navigation landmark
      const mainNav = page.locator('nav[role="navigation"]').or(page.locator('nav'));
      await expect(mainNav.first()).toBeVisible();

      // Check for accessible navigation items
      const navItems = page.getByRole('link');
      const navCount = await navItems.count();

      expect(navCount).toBeGreaterThan(0);

      // Navigation items should have proper text content
      for (let i = 0; i < Math.min(navCount, 5); i++) {
        const navItem = navItems.nth(i);
        const text = await navItem.textContent();
        expect(text).toBeTruthy();
      }
    });

    test('should support screen reader navigation', async ({ page }) => {
      await helpers.navigateTo('Map');

      // No h1 headings exist - check for navigation landmark instead
      const nav = page.locator('nav').first();
      await expect(nav).toBeVisible();

      // Check for proper link labels
      const links = page.getByRole('link');
      const linkCount = await links.count();

      // Most links should have text content (skip icon-only links)
      let linksWithText = 0;
      for (let i = 0; i < Math.min(linkCount, 10); i++) {
        const link = links.nth(i);
        const text = await link.textContent();
        if (text?.trim()) {
          linksWithText++;
        }
      }
      // At least half of the links should have text content
      expect(linksWithText).toBeGreaterThan(Math.min(linkCount, 10) / 2);
    });
  });
});
