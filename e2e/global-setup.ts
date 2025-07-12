import { chromium, FullConfig } from '@playwright/test';

async function globalSetup(config: FullConfig) {
  const { baseURL } = config.projects[0].use;

  // Launch browser for setup operations
  const browser = await chromium.launch();
  const page = await browser.newPage();

  try {
    // Wait for the server to be ready
    console.log('Checking if Dawarich server is available...');

    // Try to connect to the health endpoint
    try {
      await page.goto(baseURL + '/api/v1/health', { waitUntil: 'networkidle', timeout: 10000 });
      console.log('Health endpoint is accessible');
    } catch (error) {
      console.log('Health endpoint not available, trying main page...');
    }

    // Check if we can access the main app
    const response = await page.goto(baseURL + '/', { timeout: 15000 });
    if (!response?.ok()) {
      throw new Error(`Server not available. Status: ${response?.status()}. Make sure Dawarich is running on ${baseURL}`);
    }

    console.log('Dawarich server is ready for testing');

  } catch (error) {
    console.error('Failed to connect to Dawarich server:', error);
    console.error(`Please make sure Dawarich is running on ${baseURL}`);
    throw error;
  } finally {
    await browser.close();
  }
}

export default globalSetup;
