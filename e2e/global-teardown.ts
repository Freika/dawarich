import { chromium, FullConfig } from '@playwright/test';

async function globalTeardown(config: FullConfig) {
  const { baseURL } = config.projects[0].use;
  
  // Launch browser for cleanup operations
  const browser = await chromium.launch();
  const page = await browser.newPage();

  try {
    console.log('Running global teardown - ensuring demo user credentials are restored...');

    // Try to login with demo credentials to verify they work
    await page.goto(baseURL + '/users/sign_in');
    
    await page.getByLabel('Email').fill('demo@dawarich.app');
    await page.getByLabel('Password').fill('password');
    await page.getByRole('button', { name: 'Log in' }).click();

    // Wait for form submission
    await page.waitForLoadState('networkidle');
    
    // Check if we successfully logged in
    const currentUrl = page.url();
    
    if (currentUrl.includes('/map')) {
      console.log('Demo user credentials are working correctly');
      
      // Navigate to account settings to ensure everything is properly set
      try {
        const userDropdown = page.locator('details').filter({ hasText: 'demo@dawarich.app' });
        await userDropdown.locator('summary').click();
        await page.getByRole('link', { name: 'Account' }).click();
        
        // Verify account page loads
        await page.waitForURL(/\/users\/edit/, { timeout: 5000 });
        console.log('Account settings accessible - demo user is properly configured');
      } catch (e) {
        console.warn('Could not verify account settings, but login worked');
      }
    } else if (currentUrl.includes('/users/sign_in')) {
      console.warn('Demo user credentials may have been modified by tests');
      console.warn('Please run: User.first.update(email: "demo@dawarich.app", password: "password", password_confirmation: "password")');
    }

  } catch (error) {
    console.warn('Global teardown check failed:', error.message);
    console.warn('Demo user credentials may need to be restored manually');
    console.warn('Please run: User.first.update(email: "demo@dawarich.app", password: "password", password_confirmation: "password")');
  } finally {
    await browser.close();
  }
}

export default globalTeardown;