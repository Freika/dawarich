import { defineConfig } from '@playwright/test'

const baseURL = process.env.NATIVE_IMPORTS_BASE_URL
if (!baseURL || !['127.0.0.1', 'localhost'].includes(new URL(baseURL).hostname)) {
  throw new Error('Set NATIVE_IMPORTS_BASE_URL to the approved isolated local test stand')
}

export default defineConfig({
  testDir: '.',
  testMatch: 'native-imports.spec.js',
  workers: 1,
  retries: 0,
  timeout: 180000,
  expect: { timeout: 15000 },
  reporter: [['list'], ['json', { outputFile: 'test-results/native-imports.json' }]],
  outputDir: 'test-results/native-imports',
  use: {
    baseURL,
    browserName: 'chromium',
    headless: true,
    locale: 'en-GB',
    timezoneId: 'Europe/Berlin',
    storageState: { cookies: [], origins: [] },
    acceptDownloads: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
})
