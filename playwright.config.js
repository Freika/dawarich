import { defineConfig, devices } from "@playwright/test"

const port = Number(process.env.E2E_PORT || 3000)
const baseURL = process.env.BASE_URL || `http://localhost:${port}`

/**
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: "./e2e",
  /* Run tests in files in parallel */
  fullyParallel: true,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,
  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : undefined,
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: [["html"], ["junit", { outputFile: "test-results/results.xml" }]],
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    ...(process.env.PLAYWRIGHT_CHANNEL && {
      channel: process.env.PLAYWRIGHT_CHANNEL,
    }),
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL,

    /* Use European locale and timezone */
    locale: "en-GB",
    timezoneId: "Europe/Berlin",

    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: "on-first-retry",

    /* Take screenshot on failure */
    screenshot: "only-on-failure",

    /* Record video on failure */
    video: "retain-on-failure",
  },

  /* Configure projects for major browsers */
  projects: [
    // Setup project - runs authentication before all tests
    {
      name: "setup",
      testMatch: /.*\/setup\/auth\.setup\.js/,
    },

    {
      name: "chromium",
      testIgnore: /.*\/lite\/.*/,
      use: {
        ...devices["Desktop Chrome"],
        // Use saved authentication state
        storageState: "e2e/temp/.auth/user.json",
      },
      dependencies: ["setup"],
    },

    // Lite user setup and tests
    {
      name: "lite-setup",
      testMatch: /.*\/setup\/auth-lite\.setup\.js/,
    },
    {
      name: "lite",
      testMatch: /.*\/lite\/.*/,
      use: {
        ...devices["Desktop Chrome"],
        storageState: "e2e/temp/.auth/lite-user.json",
      },
      dependencies: ["lite-setup"],
    },
  ],

  /* Run your local dev server before starting the tests */
  webServer: {
    command: `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES WEB_CONCURRENCY=0 RAILS_ENV=development bin/rails server -p ${port}`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000,
  },
})
