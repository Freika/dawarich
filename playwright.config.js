import { defineConfig, devices } from "@playwright/test"

/**
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,
  /* Opt out of parallel tests on CI. */
  workers: 1,
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: [["html"], ["junit", { outputFile: "test-results/results.xml" }]],
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL:
      process.env.BASE_URL ||
      `http://127.0.0.1:${process.env.MAP_E2E_PORT || "3200"}`,

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
    {
      name: "setup",
      testMatch: /.*\/setup\/auth\.setup\.js/,
      use: { ...devices["Desktop Chrome"], channel: "chrome" },
    },

    {
      name: "map-editing",
      testIgnore: [/.*\/large\/.*/, /.*\/setup\/.*/],
      use: {
        ...devices["Desktop Chrome"],
        channel: "chrome",
        storageState: "e2e/temp/.auth/user.json",
      },
      dependencies: ["setup"],
    },

    {
      name: "large-setup",
      testMatch: /.*\/setup\/auth-large\.setup\.js/,
      use: { ...devices["Desktop Chrome"], channel: "chrome" },
    },
    {
      name: "large-history",
      testMatch: /.*\/large\/.*/,
      use: {
        ...devices["Desktop Chrome"],
        channel: "chrome",
        storageState: "e2e/temp/.auth/large-user.json",
      },
      dependencies: ["large-setup"],
    },
  ],

  globalTeardown: "./e2e/setup/global_teardown.js",

  webServer: {
    command: "script/start_map_e2e_server",
    url:
      process.env.BASE_URL ||
      `http://127.0.0.1:${process.env.MAP_E2E_PORT || "3200"}`,
    reuseExistingServer: false,
    timeout: 240 * 1000,
  },
})
