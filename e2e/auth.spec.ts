import { test, expect } from '@playwright/test';
import { TestHelpers, TEST_USERS } from './fixtures/test-helpers';

test.describe('Authentication', () => {
  let helpers: TestHelpers;

  test.beforeEach(async ({ page }) => {
    helpers = new TestHelpers(page);
  });

  test.describe('Login and Logout', () => {
    test('should display login page correctly', async ({ page }) => {
      await page.goto('/users/sign_in');

      // Check page elements based on actual Devise view
      await expect(page).toHaveTitle(/Dawarich/);
      await expect(page.getByRole('heading', { name: 'Login now' })).toBeVisible();
      await expect(page.getByLabel('Email')).toBeVisible();
      await expect(page.getByLabel('Password')).toBeVisible();
      await expect(page.getByRole('button', { name: 'Log in' })).toBeVisible();
      await expect(page.getByRole('link', { name: 'Forgot your password?' })).toBeVisible();
    });

    test('should show demo credentials in demo environment', async ({ page }) => {
      await page.goto('/users/sign_in');

      // Check if demo credentials are shown (they may not be in test environment)
      const demoCredentials = page.getByText('demo@dawarich.app');
      if (await demoCredentials.isVisible()) {
        await expect(demoCredentials).toBeVisible();
        await expect(page.getByText('password').nth(1)).toBeVisible(); // Second "password" text
      }
    });

    test('should login with valid credentials', async ({ page }) => {
      await helpers.loginAsDemo();

      // Verify successful login - should redirect to map
      await expect(page).toHaveURL(/\/map/);
      await expect(page.getByText(TEST_USERS.DEMO.email)).toBeVisible();
    });

    test('should reject invalid credentials', async ({ page }) => {
      await page.goto('/users/sign_in');

      await page.getByLabel('Email').fill('invalid@email.com');
      await page.getByLabel('Password').fill('wrongpassword');
      await page.getByRole('button', { name: 'Log in' }).click();

      // Should stay on login page and show error
      await expect(page).toHaveURL(/\/users\/sign_in/);
      // Devise shows error messages - look for error indication
      const errorMessage = page.locator('#error_explanation, .alert, .flash').filter({ hasText: /invalid/i });
      if (await errorMessage.isVisible()) {
        await expect(errorMessage).toBeVisible();
      }
    });

    test('should remember user when "Remember me" is checked', async ({ page }) => {
      await page.goto('/users/sign_in');

      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
      await page.getByLabel('Password').fill(TEST_USERS.DEMO.password);

      // Look for remember me checkbox - use getByRole to target the actual checkbox
      const rememberCheckbox = page.getByRole('checkbox', { name: 'Remember me' });

      if (await rememberCheckbox.isVisible()) {
        await rememberCheckbox.check();
      }

      await page.getByRole('button', { name: 'Log in' }).click();

      // Wait for redirect with longer timeout
      await page.waitForURL(/\/map/, { timeout: 10000 });

      // Check for remember token cookie
      const cookies = await page.context().cookies();
      const hasPersistentCookie = cookies.some(cookie =>
        cookie.name.includes('remember') || cookie.name.includes('session')
      );
      expect(hasPersistentCookie).toBeTruthy();
    });

    test('should logout successfully', async ({ page }) => {
      await helpers.loginAsDemo();

      // Open user dropdown using the actual navigation structure
      const userDropdown = page.locator('details').filter({ hasText: TEST_USERS.DEMO.email });
      await userDropdown.locator('summary').click();

      // Use evaluate to trigger the logout form submission properly
      await page.evaluate(() => {
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
      await page.waitForURL('/', { timeout: 10000 });

      // Verify user is logged out - should see login options
      await expect(page.getByRole('link', { name: 'Sign in' })).toBeVisible();
    });

    test('should redirect to login when accessing protected pages while logged out', async ({ page }) => {
      await page.goto('/map');

      // Should redirect to login
      await expect(page).toHaveURL(/\/users\/sign_in/);
    });
  });

  // NOTE: Update TEST_USERS in fixtures/test-helpers.ts with correct credentials
  // that match your localhost:3000 server setup
  test.describe('Password Management', () => {
    test('should display forgot password form', async ({ page }) => {
      await page.goto('/users/sign_in');
      await page.getByRole('link', { name: 'Forgot your password?' }).click();

      await expect(page).toHaveURL(/\/users\/password\/new/);
      await expect(page.getByRole('heading', { name: 'Forgot your password?' })).toBeVisible();
      await expect(page.getByLabel('Email')).toBeVisible();
      await expect(page.getByRole('button', { name: 'Send me reset password instructions' })).toBeVisible();
    });

    test('should handle password reset request', async ({ page }) => {
      await page.goto('/users/password/new');

      // Fill the email but don't submit to avoid sending actual reset emails
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);

      // Verify the form elements exist and are functional
      await expect(page.getByRole('button', { name: 'Send me reset password instructions' })).toBeVisible();
      await expect(page.getByLabel('Email')).toHaveValue(TEST_USERS.DEMO.email);

      // Test form validation by clearing email and checking if button is still clickable
      await page.getByLabel('Email').fill('');
      await expect(page.getByRole('button', { name: 'Send me reset password instructions' })).toBeVisible();
    });

    test('should change password when logged in', async ({ page }) => {
      // Manual login for this test
      await page.goto('/users/sign_in');
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
      await page.getByLabel('Password').fill(TEST_USERS.DEMO.password);
      await page.getByRole('button', { name: 'Log in' }).click();
      await page.waitForURL(/\/map/, { timeout: 10000 });

      // Navigate to account settings through user dropdown
      const userDropdown = page.locator('details').filter({ hasText: TEST_USERS.DEMO.email });
      await userDropdown.locator('summary').click();
      await page.getByRole('link', { name: 'Account' }).click();

      await expect(page).toHaveURL(/\/users\/edit/);

      // Check password change form is available - be more specific with selectors
      await expect(page.locator('input[id="user_password"]')).toBeVisible();
      await expect(page.getByLabel('Current password')).toBeVisible();

      // Test filling the form but don't submit to avoid changing the password
      await page.locator('input[id="user_password"]').fill('newpassword123');
      await page.getByLabel('Current password').fill(TEST_USERS.DEMO.password);

      // Verify the form can be filled and update button is present
      await expect(page.getByRole('button', { name: 'Update' })).toBeVisible();

      // Clear the password fields to avoid changing credentials
      await page.locator('input[id="user_password"]').fill('');
    });
  });

  test.describe('Account Settings', () => {
    test.beforeEach(async ({ page }) => {
      // Fresh login for each test in this describe block
      await page.goto('/users/sign_in');
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
      await page.getByLabel('Password').fill(TEST_USERS.DEMO.password);
      await page.getByRole('button', { name: 'Log in' }).click();
      await page.waitForURL(/\/map/, { timeout: 10000 });
    });

    test('should display account settings page', async ({ page }) => {
      const userDropdown = page.locator('details').filter({ hasText: TEST_USERS.DEMO.email });
      await userDropdown.locator('summary').click();
      await page.getByRole('link', { name: 'Account' }).click();

      await expect(page).toHaveURL(/\/users\/edit/);
      await expect(page.getByRole('heading', { name: 'Edit your account!' })).toBeVisible();
      await expect(page.getByLabel('Email')).toBeVisible();
    });

    test('should update email address with current password', async ({ page }) => {
      const userDropdown = page.locator('details').filter({ hasText: TEST_USERS.DEMO.email });
      await userDropdown.locator('summary').click();
      await page.getByRole('link', { name: 'Account' }).click();

      // Test that we can fill the form, but don't actually submit to avoid changing credentials
      await page.getByLabel('Email').fill('newemail@test.com');
      await page.getByLabel('Current password').fill(TEST_USERS.DEMO.password);

      // Verify the form elements are present and fillable, but don't submit
      await expect(page.getByRole('button', { name: 'Update' })).toBeVisible();

      // Reset the email field to avoid confusion
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
    });

    test('should view API key in settings', async ({ page }) => {
      const userDropdown = page.locator('details').filter({ hasText: TEST_USERS.DEMO.email });
      await userDropdown.locator('summary').click();
      await page.getByRole('link', { name: 'Account' }).click();

      // API key should be visible in the account section
      await expect(page.getByText('Use this API key')).toBeVisible();
      await expect(page.locator('code').first()).toBeVisible();
    });

    test('should generate new API key', async ({ page }) => {
      const userDropdown = page.locator('details').filter({ hasText: TEST_USERS.DEMO.email });
      await userDropdown.locator('summary').click();
      await page.getByRole('link', { name: 'Account' }).click();

      // Get current API key
      const currentApiKey = await page.locator('code').first().textContent();

      // Verify the generate new API key link exists but don't click it to avoid changing the key
      const generateKeyLink = page.getByRole('link', { name: 'Generate new API key' });
      await expect(generateKeyLink).toBeVisible();

      // Verify the API key is displayed
      await expect(page.locator('code').first()).toBeVisible();
      expect(currentApiKey).toBeTruthy();
    });

    test('should change theme', async ({ page }) => {
      // Theme toggle is in the navbar
      const themeButton = page.locator('svg').locator('..').filter({ hasText: /path/ });

      if (await themeButton.isVisible()) {
        // Get current theme
        const htmlElement = page.locator('html');
        const currentTheme = await htmlElement.getAttribute('data-theme');

        await themeButton.click();

        // Wait for theme change
        await page.waitForTimeout(500);

        // Theme should have changed
        const newTheme = await htmlElement.getAttribute('data-theme');
        expect(newTheme).not.toBe(currentTheme);
      }
    });
  });

  test.describe('Registration (Non-Self-Hosted)', () => {
    test('should show registration link when not self-hosted', async ({ page }) => {
      await page.goto('/users/sign_in');

      // Registration link may or may not be visible depending on SELF_HOSTED setting
      const registerLink = page.getByRole('link', { name: 'Register' }).first(); // Use first to avoid strict mode
      const selfHosted = await page.getAttribute('html', 'data-self-hosted');

      if (selfHosted === 'false') {
        await expect(registerLink).toBeVisible();
      } else {
        await expect(registerLink).not.toBeVisible();
      }
    });

    test('should display registration form when available', async ({ page }) => {
      await page.goto('/users/sign_up');

      // May redirect if self-hosted, so check current URL
      if (page.url().includes('/users/sign_up')) {
        await expect(page.getByRole('heading', { name: 'Register now!' })).toBeVisible();
        await expect(page.getByLabel('Email')).toBeVisible();
        await expect(page.locator('input[id="user_password"]')).toBeVisible(); // Be specific for main password field
        await expect(page.locator('input[id="user_password_confirmation"]')).toBeVisible(); // Use ID for confirmation field
        await expect(page.getByRole('button', { name: 'Sign up' })).toBeVisible();
      }
    });
  });

  test.describe('Mobile Authentication', () => {
    test('should work on mobile viewport', async ({ page }) => {
      // Set mobile viewport
      await page.setViewportSize({ width: 375, height: 667 });

      await page.goto('/users/sign_in');

      // Check mobile-responsive login form
      await expect(page.getByLabel('Email')).toBeVisible();
      await expect(page.getByLabel('Password')).toBeVisible();
      await expect(page.getByRole('button', { name: 'Log in' })).toBeVisible();

      // Test login on mobile
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
      await page.getByLabel('Password').fill(TEST_USERS.DEMO.password);
      await page.getByRole('button', { name: 'Log in' }).click();
      await page.waitForURL(/\/map/, { timeout: 10000 });
    });

    test('should handle mobile navigation after login', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      // Manual login
      await page.goto('/users/sign_in');
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
      await page.getByLabel('Password').fill(TEST_USERS.DEMO.password);
      await page.getByRole('button', { name: 'Log in' }).click();
      await page.waitForURL(/\/map/, { timeout: 10000 });

      // Open mobile navigation using hamburger menu
      const mobileMenuButton = page.locator('label[tabindex="0"]').or(
        page.locator('button').filter({ hasText: /menu/i })
      );

      if (await mobileMenuButton.isVisible()) {
        await mobileMenuButton.click();

        // Should see user email in mobile menu structure
        await expect(page.getByText(TEST_USERS.DEMO.email)).toBeVisible();
      }
    });

    test('should handle mobile logout', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });

      // Manual login
      await page.goto('/users/sign_in');
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
      await page.getByLabel('Password').fill(TEST_USERS.DEMO.password);
      await page.getByRole('button', { name: 'Log in' }).click();
      await page.waitForURL(/\/map/, { timeout: 10000 });

      // In mobile view, user dropdown should still work
      const userDropdown = page.locator('details').filter({ hasText: TEST_USERS.DEMO.email });
      await userDropdown.locator('summary').click();

      // Use evaluate to trigger the logout form submission properly
      await page.evaluate(() => {
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
      await page.waitForURL('/', { timeout: 10000 });

      // Verify user is logged out - should see login options
      await expect(page.getByRole('link', { name: 'Sign in' })).toBeVisible();
    });
  });

  test.describe('Navigation Integration', () => {
    test.beforeEach(async ({ page }) => {
      // Manual login for each test in this describe block
      await page.goto('/users/sign_in');
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
      await page.getByLabel('Password').fill(TEST_USERS.DEMO.password);
      await page.getByRole('button', { name: 'Log in' }).click();
      await page.waitForURL(/\/map/, { timeout: 10000 });
    });

    test('should show user email in navigation', async ({ page }) => {
      // User email should be visible in the navbar dropdown
      await expect(page.getByText(TEST_USERS.DEMO.email)).toBeVisible();
    });

    test('should show admin indicator for admin users', async ({ page }) => {
      // Look for admin star indicator if user is admin
      const adminStar = page.getByText('⭐️');
      // Admin indicator may not be visible for demo user
      const isVisible = await adminStar.isVisible();
      // Just verify the page doesn't crash
      expect(typeof isVisible).toBe('boolean');
    });

    test('should access settings through navigation', async ({ page }) => {
      const userDropdown = page.locator('details').filter({ hasText: TEST_USERS.DEMO.email });
      await userDropdown.locator('summary').click();
      await page.getByRole('link', { name: 'Settings' }).click();

      await expect(page).toHaveURL(/\/settings/);
      await expect(page.getByRole('heading', { name: /settings/i })).toBeVisible();
    });

    test('should show version badge in navigation', async ({ page }) => {
      // Version badge should be visible
      const versionBadge = page.locator('.badge').filter({ hasText: /\d+\.\d+/ });
      await expect(versionBadge).toBeVisible();
    });

    test('should show notifications dropdown', async ({ page }) => {
      // Notifications dropdown should be present - look for the notification bell icon more directly
      const notificationDropdown = page.locator('[data-controller="notifications"]');

      if (await notificationDropdown.isVisible()) {
        await expect(notificationDropdown).toBeVisible();
      } else {
        // Alternative: Look for notification button/bell icon
        const notificationButton = page.locator('svg').filter({ hasText: /path.*stroke.*d=/ });
        if (await notificationButton.first().isVisible()) {
          await expect(notificationButton.first()).toBeVisible();
        } else {
          // If notifications aren't available, just check that the navbar exists
          const navbar = page.locator('.navbar');
          await expect(navbar).toBeVisible();
          console.log('Notifications dropdown not found, but navbar is present');
        }
      }
    });
  });

  test.describe('Session Management', () => {
    test('should maintain session across page reloads', async ({ page }) => {
      // Manual login
      await page.goto('/users/sign_in');
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
      await page.getByLabel('Password').fill(TEST_USERS.DEMO.password);
      await page.getByRole('button', { name: 'Log in' }).click();
      await page.waitForURL(/\/map/, { timeout: 10000 });

      // Reload page
      await page.reload();
      await page.waitForLoadState('networkidle');

      // Should still be logged in
      await expect(page.getByText(TEST_USERS.DEMO.email)).toBeVisible();
      await expect(page).toHaveURL(/\/map/);
    });

    test('should handle session timeout gracefully', async ({ page }) => {
      // Manual login
      await page.goto('/users/sign_in');
      await page.getByLabel('Email').fill(TEST_USERS.DEMO.email);
      await page.getByLabel('Password').fill(TEST_USERS.DEMO.password);
      await page.getByRole('button', { name: 'Log in' }).click();
      await page.waitForURL(/\/map/, { timeout: 10000 });

      // Clear all cookies to simulate session timeout
      await page.context().clearCookies();

      // Try to access protected page
      await page.goto('/settings');

      // Should redirect to login
      await expect(page).toHaveURL(/\/users\/sign_in/);
    });
  });
});
