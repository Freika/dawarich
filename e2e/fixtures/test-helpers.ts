import { Page, expect } from '@playwright/test';

export interface TestUser {
  email: string;
  password: string;
  isAdmin?: boolean;
}

export class TestHelpers {
  constructor(private page: Page) {}

  /**
   * Navigate to the home page
   */
  async goToHomePage() {
    await this.page.goto('/');
    await expect(this.page).toHaveTitle(/Dawarich/);
  }

  /**
   * Login with provided credentials
   */
  async login(user: TestUser) {
    await this.page.goto('/users/sign_in');

    // Fill in login form using actual Devise structure
    await this.page.getByLabel('Email').fill(user.email);
    await this.page.getByLabel('Password').fill(user.password);

    // Submit login
    await this.page.getByRole('button', { name: 'Log in' }).click();

    // Wait for form submission to complete
    await this.page.waitForLoadState('networkidle');
    await this.page.waitForTimeout(1000);

    // Check if login failed (stayed on login page with error)
    const currentUrl = this.page.url();
    if (currentUrl.includes('/users/sign_in')) {
      // Check for error messages
      const errorMessage = this.page.locator('.bg-red-100, .text-red-700, .alert-error');
      if (await errorMessage.isVisible()) {
        throw new Error(`Login failed for ${user.email}. Possible credential mismatch.`);
      }
    }

    // Wait for navigation to complete - use the same approach as working tests
    await this.page.waitForURL(/\/map/, { timeout: 10000 });

    // Verify user is logged in by checking for email in navbar
    await expect(this.page.getByText(user.email)).toBeVisible({ timeout: 5000 });
  }

  /**
   * Login with demo credentials with retry logic
   */
  async loginAsDemo() {
    // Try login with retry mechanism in case of transient failures
    let attempts = 0;
    const maxAttempts = 3;
    
    while (attempts < maxAttempts) {
      try {
        await this.login({ email: 'demo@dawarich.app', password: 'password' });
        return; // Success, exit the retry loop
      } catch (error) {
        attempts++;
        if (attempts >= maxAttempts) {
          throw new Error(`Login failed after ${maxAttempts} attempts. Last error: ${error.message}. The demo user credentials may need to be reset. Please run: User.first.update(email: 'demo@dawarich.app', password: 'password', password_confirmation: 'password')`);
        }
        
        // Wait a bit before retrying
        await this.page.waitForTimeout(1000);
        console.log(`Login attempt ${attempts} failed, retrying...`);
      }
    }
  }

  /**
   * Logout current user using actual navigation structure
   */
  async logout() {
    // Open user dropdown using the actual navigation structure - use first() to avoid strict mode
    const userDropdown = this.page.locator('details').filter({ hasText: /@/ }).first();
    await userDropdown.locator('summary').click();

    // Use evaluate to trigger the logout form submission properly
    await this.page.evaluate(() => {
      const logoutLink = document.querySelector('a[href="/users/sign_out"]');
      if (logoutLink) {
        // Create a form and submit it with DELETE method (Rails UJS style)
        const form = document.createElement('form');
        form.action = '/users/sign_out';
        form.method = 'post';
        form.style.display = 'none';

        // Add method override for DELETE
        const methodInput = document.createElement('input');
        methodInput.type = 'hidden';
        methodInput.name = '_method';
        methodInput.value = 'delete';
        form.appendChild(methodInput);

        // Add CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]');
        if (csrfToken) {
          const csrfInput = document.createElement('input');
          csrfInput.type = 'hidden';
          csrfInput.name = 'authenticity_token';
          const tokenValue = csrfToken.getAttribute('content');
          if (tokenValue) {
            csrfInput.value = tokenValue;
          }
          form.appendChild(csrfInput);
        }

        document.body.appendChild(form);
        form.submit();
      }
    });

    // Wait for redirect and navigate to home to verify logout
    await this.page.waitForURL('/', { timeout: 10000 });

    // Verify user is logged out - should see login options
    await expect(this.page.getByRole('link', { name: 'Sign in' })).toBeVisible();
  }

  /**
   * Navigate to specific section using actual navigation structure
   */
  async navigateTo(section: 'Map' | 'Trips' | 'Stats' | 'Points' | 'Visits' | 'Imports' | 'Exports' | 'Settings') {
    // Check if already on the target page
    const currentUrl = this.page.url();
    const targetPath = section.toLowerCase();

    if (section === 'Map' && (currentUrl.includes('/map') || currentUrl.endsWith('/'))) {
      // Already on map page, just navigate directly
      await this.page.goto('/map');
      await this.page.waitForLoadState('networkidle');
      return;
    }

    // Handle nested menu items that are in "My data" dropdown
    if (['Points', 'Visits', 'Imports', 'Exports'].includes(section)) {
      // Open "My data" dropdown - select the visible one (not the hidden mobile version)
      const myDataDropdown = this.page.locator('details').filter({ hasText: 'My data' }).and(this.page.locator(':visible'));
      await myDataDropdown.locator('summary').click();

      // Handle special cases for visit links
      if (section === 'Visits') {
        await this.page.getByRole('link', { name: 'Visits & Places' }).click();
      } else {
        await this.page.getByRole('link', { name: section }).click();
      }
    } else if (section === 'Settings') {
      // Settings is accessed through user dropdown - use first() to avoid strict mode
      const userDropdown = this.page.locator('details').filter({ hasText: /@/ }).first();
      await userDropdown.locator('summary').click();
      await this.page.getByRole('link', { name: 'Settings' }).click();
    } else {
      // Direct navigation items (Map, Trips, Stats)
      // Try to find the link, if not found, navigate directly
      const navLink = this.page.getByRole('link', { name: section });
      try {
        await navLink.click({ timeout: 2000 });
      } catch (error) {
        // If link not found, navigate directly to the page
        await this.page.goto(`/${targetPath}`);
      }
    }

    // Wait for page to load
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for map to be loaded and interactive
   */
  async waitForMap() {
    // Wait for map container to be visible - the #map element is always present
    await expect(this.page.locator('#map')).toBeVisible();

    // Wait for map controls to be available (indicates map is functional)
    await expect(this.page.getByRole('button', { name: 'Zoom in' })).toBeVisible();

    // Wait a bit more for any async loading
    await this.page.waitForTimeout(500);
  }

  /**
   * Check if notification with specific text is visible
   */
  async expectNotification(text: string, type: 'success' | 'error' | 'info' = 'success') {
    // Use actual flash message structure from Dawarich
    const notification = this.page.locator('#flash-messages .alert, #flash-messages div').filter({ hasText: text });
    await expect(notification.first()).toBeVisible();
  }

  /**
   * Upload a file using the file input
   */
  async uploadFile(inputSelector: string, filePath: string) {
    const fileInput = this.page.locator(inputSelector);
    await fileInput.setInputFiles(filePath);
  }

  /**
   * Wait for background job to complete (polling approach)
   */
  async waitForJobCompletion(jobName: string, timeout = 30000) {
    const startTime = Date.now();

    while (Date.now() - startTime < timeout) {
      // Check if there's a completion notification in flash messages
      const completionNotification = this.page.locator('#flash-messages').filter({
        hasText: new RegExp(jobName + '.*(completed|finished|done)', 'i')
      });

      if (await completionNotification.isVisible()) {
        return;
      }

      // Wait before checking again
      await this.page.waitForTimeout(1000);
    }

    throw new Error(`Job "${jobName}" did not complete within ${timeout}ms`);
  }

  /**
   * Generate test file content for imports
   */
  createTestGeoJSON(pointCount = 10): string {
    const features: any[] = [];
    const baseTime = Date.now() - (pointCount * 60 * 1000); // Points every minute

    for (let i = 0; i < pointCount; i++) {
      features.push({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [-74.0060 + (i * 0.001), 40.7128 + (i * 0.001)]
        },
        properties: {
          timestamp: Math.floor((baseTime + (i * 60 * 1000)) / 1000)
        }
      });
    }

    return JSON.stringify({
      type: 'FeatureCollection',
      features
    });
  }

  /**
   * Check if element is visible on mobile viewports
   */
  async isMobileViewport(): Promise<boolean> {
    const viewport = this.page.viewportSize();
    return viewport ? viewport.width < 768 : false;
  }

  /**
   * Handle mobile navigation (hamburger menu) using actual structure
   */
  async openMobileNavigation() {
    if (await this.isMobileViewport()) {
      // Use actual mobile menu button structure from navbar
      const mobileMenuButton = this.page.locator('label[tabindex="0"]').or(
        this.page.locator('button').filter({ hasText: /menu/i })
      );

      if (await mobileMenuButton.isVisible()) {
        await mobileMenuButton.click();
      }
    }
  }

  /**
   * Access account settings through user dropdown
   */
  async goToAccountSettings() {
    const userDropdown = this.page.locator('details').filter({ hasText: /@/ }).first();
    await userDropdown.locator('summary').click();
    await this.page.getByRole('link', { name: 'Account' }).click();

    await expect(this.page).toHaveURL(/\/users\/edit/);
  }

  /**
   * Check if user is admin by looking for admin indicator
   */
  async isUserAdmin(): Promise<boolean> {
    const adminStar = this.page.getByText('⭐️');
    return await adminStar.isVisible();
  }

  /**
   * Get current theme from HTML data attribute
   */
  async getCurrentTheme(): Promise<string | null> {
    return await this.page.getAttribute('html', 'data-theme');
  }

  /**
   * Check if app is in self-hosted mode
   */
  async isSelfHosted(): Promise<boolean> {
    const selfHosted = await this.page.getAttribute('html', 'data-self-hosted');
    return selfHosted === 'true';
  }

  /**
   * Toggle theme using navbar theme button
   */
  async toggleTheme() {
    // Theme button is an SVG inside a link
    const themeButton = this.page.locator('svg').locator('..').filter({ hasText: /path/ });

    if (await themeButton.isVisible()) {
      await themeButton.click();
      // Wait for theme change to take effect
      await this.page.waitForTimeout(500);
    }
  }

  /**
   * Check if notifications dropdown is available
   */
  async hasNotifications(): Promise<boolean> {
    const notificationButton = this.page.locator('svg').locator('..').filter({ hasText: /path.*stroke/ });
    return await notificationButton.first().isVisible();
  }

  /**
   * Open notifications dropdown
   */
  async openNotifications() {
    if (await this.hasNotifications()) {
      const notificationButton = this.page.locator('svg').locator('..').filter({ hasText: /path.*stroke/ }).first();
      await notificationButton.click();
    }
  }

  /**
   * Generate new API key from account settings
   */
  async generateNewApiKey() {
    await this.goToAccountSettings();

    // Get current API key
    const currentApiKey = await this.page.locator('code').first().textContent();

    // Click generate new API key button
    await this.page.getByRole('link', { name: 'Generate new API key' }).click();

    // Wait for page to reload with new key
    await this.page.waitForLoadState('networkidle');

    // Return new API key
    const newApiKey = await this.page.locator('code').first().textContent();
    return { currentApiKey, newApiKey };
  }

  /**
   * Access specific settings section
   */
  async goToSettings(section?: 'Maps' | 'Background Jobs' | 'Users') {
    await this.navigateTo('Settings');

    if (section) {
      // Click on the specific settings tab
      await this.page.getByRole('tab', { name: section }).click();
      await this.page.waitForLoadState('networkidle');
    }
  }
}

// Test data constants
export const TEST_USERS = {
  DEMO: {
    email: 'demo@dawarich.app',
    password: 'password'
  },
  ADMIN: {
    email: 'admin@dawarich.app',
    password: 'password',
    isAdmin: true
  }
};

export const TEST_COORDINATES = {
  NYC: { lat: 40.7128, lon: -74.0060, name: 'New York City' },
  LONDON: { lat: 51.5074, lon: -0.1278, name: 'London' },
  TOKYO: { lat: 35.6762, lon: 139.6503, name: 'Tokyo' }
};
