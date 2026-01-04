import { test as setup, expect } from '@playwright/test';
import { disableGlobeProjection } from '../v2/helpers/setup.js';

const authFile = 'e2e/temp/.auth/user.json';

setup('authenticate', async ({ page }) => {
  // Navigate to login page with more lenient waiting
  await page.goto('/users/sign_in', {
    waitUntil: 'domcontentloaded',
    timeout: 30000
  });

  // Fill in credentials
  await page.fill('input[name="user[email]"]', 'demo@dawarich.app');
  await page.fill('input[name="user[password]"]', 'password');

  // Click login button
  await page.click('input[type="submit"][value="Log in"]');

  // Wait for successful navigation to map (v1 or v2 depending on user preference)
  await page.waitForURL(/\/map(\/v[12])?/, { timeout: 10000 });

  // Disable globe projection to ensure consistent E2E test behavior
  await disableGlobeProjection(page);

  // Save authentication state
  await page.context().storageState({ path: authFile });
});
