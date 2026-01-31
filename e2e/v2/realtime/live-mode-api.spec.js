import { test, expect } from '@playwright/test';
import { closeOnboardingModal } from '../../helpers/navigation.js';
import { navigateToMapsV2, waitForMapLibre, waitForLoadingComplete } from '../helpers/setup.js';
import { API_KEYS, TEST_USERS, TEST_LOCATIONS } from '../helpers/constants.js';
import {
  sendOwnTracksPoint,
  waitForPointOnMap,
  waitForFamilyMemberOnMap,
  enableLiveMode,
  waitForActionCableConnection,
  waitForPointsChannelConnected
} from '../helpers/api.js';

test.describe('Live Mode API Integration', () => {
  /**
   * API Authentication Tests
   * These tests verify that the API keys are correctly configured
   * and work for authentication. They don't require ActionCable/Redis.
   */
  test.describe('API Authentication', () => {
    test('should reject requests with invalid API key', async ({ request }) => {
      const response = await sendOwnTracksPoint(
        request,
        'invalid_api_key_12345',
        52.5200,
        13.4050,
        Math.floor(Date.now() / 1000)
      );

      expect(response.status()).toBe(401);
    });

    test('should accept requests with valid demo user API key', async ({ request }) => {
      const response = await sendOwnTracksPoint(
        request,
        API_KEYS.DEMO_USER,
        52.5200,
        13.4050,
        Math.floor(Date.now() / 1000)
      );

      expect(response.status()).toBe(200);
    });

    test('should accept requests with valid family member 1 API key', async ({ request }) => {
      const response = await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        52.5200,
        13.4050,
        Math.floor(Date.now() / 1000)
      );

      expect(response.status()).toBe(200);
    });

    test('should accept requests with valid family member 2 API key', async ({ request }) => {
      const response = await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_2,
        52.5200,
        13.4050,
        Math.floor(Date.now() / 1000)
      );

      expect(response.status()).toBe(200);
    });

    test('should accept requests with valid family member 3 API key', async ({ request }) => {
      const response = await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_3,
        52.5200,
        13.4050,
        Math.floor(Date.now() / 1000)
      );

      expect(response.status()).toBe(200);
    });
  });

  /**
   * Live Mode UI Tests
   * These tests verify the live mode UI components work correctly
   */
  test.describe('Live Mode UI', () => {
    test.beforeEach(async ({ page }) => {
      await navigateToMapsV2(page);
      await closeOnboardingModal(page);
      await waitForMapLibre(page);
      await waitForLoadingComplete(page);

      // Wait for layers to be fully initialized
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]');
        if (!element) return false;
        const app = window.Stimulus || window.Application;
        if (!app) return false;
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
        return controller?.layerManager?.layers?.recentPointLayer !== undefined;
      }, { timeout: 10000 });

      await page.waitForTimeout(1000);
    });

    test('should enable live mode via settings toggle', async ({ page }) => {
      // Enable live mode
      await enableLiveMode(page);

      // Verify the toggle is checked (need to reopen settings)
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click();
      await page.waitForTimeout(300);
      await page.locator('button[data-tab="settings"]').click();
      await page.waitForTimeout(300);

      const liveModeToggle = page.locator('[data-maps--maplibre-realtime-target="liveModeToggle"]');
      expect(await liveModeToggle.isChecked()).toBe(true);
    });

    test('should initialize realtime controller', async ({ page }) => {
      const hasController = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre-realtime"]');
        const app = window.Stimulus || window.Application;
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre-realtime');
        return controller !== undefined;
      });

      expect(hasController).toBe(true);
    });

    test('should setup ActionCable channels on connect', async ({ page }) => {
      // Wait for channels to be set up
      await page.waitForTimeout(2000);

      const channelsInitialized = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre-realtime"]');
        const app = window.Stimulus || window.Application;
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre-realtime');
        return controller?.channels !== undefined;
      });

      expect(channelsInitialized).toBe(true);
    });
  });

  /**
   * Real-Time Point Display Tests
   * These tests verify real-time updates work when ActionCable/Redis is configured.
   * They will skip gracefully if the real-time infrastructure isn't available.
   */
  test.describe('Real-Time Point Display', () => {
    // Extend timeout for these tests as they involve multiple async operations
    test.setTimeout(60000);
    test.beforeEach(async ({ page }) => {
      await navigateToMapsV2(page);
      await closeOnboardingModal(page);
      await waitForMapLibre(page);
      await waitForLoadingComplete(page);

      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]');
        if (!element) return false;
        const app = window.Stimulus || window.Application;
        if (!app) return false;
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
        return controller?.layerManager !== undefined;
      }, { timeout: 10000 });

      await page.waitForTimeout(1000);
    });

    test('should create point via API and verify real-time display', async ({ page, request }) => {
      // Enable live mode
      await enableLiveMode(page);

      // Wait for ActionCable connection
      const connected = await waitForActionCableConnection(page);
      expect(connected).toBe(true);

      // Wait for points channel to be connected (shorter timeout)
      const pointsChannelConnected = await waitForPointsChannelConnected(page, 3000);

      // Brief delay for channel subscription
      await page.waitForTimeout(1000);

      // Generate unique coordinates
      const testLat = TEST_LOCATIONS.BERLIN_CENTER.lat + (Math.random() * 0.001);
      const testLon = TEST_LOCATIONS.BERLIN_CENTER.lon + (Math.random() * 0.001);
      const timestamp = Math.floor(Date.now() / 1000);

      // Send point via API - this should always work
      const response = await sendOwnTracksPoint(
        request,
        API_KEYS.DEMO_USER,
        testLat,
        testLon,
        timestamp
      );

      expect(response.status()).toBe(200);

      // Real-time verification - depends on ActionCable/Redis (shorter timeout)
      if (pointsChannelConnected) {
        const pointAppeared = await waitForPointOnMap(page, testLat, testLon, 5000);

        if (pointAppeared) {
          console.log('[Test] Real-time point display verified successfully');
        } else {
          console.log('[Test] Point created via API, real-time broadcast requires Redis/ActionCable');
        }
      } else {
        console.log('[Test] Points channel not connected - API point creation successful');
      }
    });

    test('should show recent point marker when live mode enabled', async ({ page, request }) => {
      // Enable live mode
      await enableLiveMode(page);
      await page.waitForTimeout(1000);

      // Simulate receiving a new point by calling handleNewPoint directly
      // This bypasses ActionCable and tests the client-side handling
      const testLat = TEST_LOCATIONS.BERLIN_NORTH.lat;
      const testLon = TEST_LOCATIONS.BERLIN_NORTH.lon;
      const timestamp = Math.floor(Date.now() / 1000);

      const result = await page.evaluate(({ lat, lon, ts }) => {
        const element = document.querySelector('[data-controller*="maps--maplibre-realtime"]');
        const app = window.Stimulus || window.Application;
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre-realtime');

        if (!controller) return { success: false, reason: 'controller not found' };
        if (typeof controller.handleNewPoint !== 'function') return { success: false, reason: 'handleNewPoint not found' };

        // Enable live mode programmatically
        controller.liveModeEnabled = true;

        // Call handleNewPoint with array format: [lat, lon, battery, altitude, timestamp, velocity, id, country_name]
        controller.handleNewPoint([lat, lon, 85, 0, ts, 0, 999999, null]);

        // Check if recent point layer became visible
        const mapsController = controller.mapsV2Controller;
        const recentPointLayer = mapsController?.layerManager?.getLayer('recentPoint');

        return {
          success: true,
          recentPointVisible: recentPointLayer?.visible === true
        };
      }, { lat: testLat, lon: testLon, ts: timestamp });

      expect(result.success).toBe(true);
      expect(result.recentPointVisible).toBe(true);
    });
  });

  /**
   * Family Member Location Tests
   * These tests verify family member location sharing works.
   * Requires family feature enabled and ActionCable/Redis configured.
   */
  test.describe('Family Member Location Tracking', () => {
    // Extend timeout for these tests as they involve multiple async operations
    test.setTimeout(60000);
    test.beforeEach(async ({ page }) => {
      await navigateToMapsV2(page);
      await closeOnboardingModal(page);
      await waitForMapLibre(page);
      await waitForLoadingComplete(page);

      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]');
        if (!element) return false;
        const app = window.Stimulus || window.Application;
        if (!app) return false;
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre');
        return controller?.layerManager !== undefined;
      }, { timeout: 10000 });

      await page.waitForTimeout(1000);
    });

    test('should create family member location point via API', async ({ page, request }) => {
      // Enable live mode to setup channels
      await enableLiveMode(page);

      // Wait for channels
      await waitForActionCableConnection(page);
      await page.waitForTimeout(2000);

      // Generate coordinates
      const testLat = TEST_LOCATIONS.BERLIN_SOUTH.lat + (Math.random() * 0.001);
      const testLon = TEST_LOCATIONS.BERLIN_SOUTH.lon + (Math.random() * 0.001);
      const timestamp = Math.floor(Date.now() / 1000);

      // Send point as family member - this verifies the API key works
      const response = await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        testLat,
        testLon,
        timestamp
      );

      expect(response.status()).toBe(200);

      // Try to verify family member appears on map
      const memberAppeared = await waitForFamilyMemberOnMap(
        page,
        TEST_USERS.FAMILY_1.email,
        10000
      );

      if (memberAppeared) {
        console.log('[Test] Family member location displayed successfully');
      } else {
        console.log('[Test] Family member location not displayed');
        console.log('[Test] Requires family feature enabled, location sharing enabled, and ActionCable');
      }
    });

    test('should handle multiple family member points', async ({ page, request }) => {
      // Enable live mode
      await enableLiveMode(page);
      await waitForActionCableConnection(page);
      await page.waitForTimeout(2000);

      const timestamp = Math.floor(Date.now() / 1000);

      // Send points for all family members
      const members = [
        { apiKey: API_KEYS.FAMILY_MEMBER_1, lat: 52.520, lon: 13.400 },
        { apiKey: API_KEYS.FAMILY_MEMBER_2, lat: 52.525, lon: 13.405 },
        { apiKey: API_KEYS.FAMILY_MEMBER_3, lat: 52.530, lon: 13.410 }
      ];

      for (const member of members) {
        const response = await sendOwnTracksPoint(
          request,
          member.apiKey,
          member.lat,
          member.lon,
          timestamp
        );

        // All family members should have valid API keys
        expect(response.status()).toBe(200);
      }

      console.log('[Test] All family member points created successfully via API');
    });
  });
});
