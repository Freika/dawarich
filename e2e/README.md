# E2E Tests

End-to-end tests for Dawarich using Playwright.

## Running Tests

```bash
# Run all tests
npx playwright test

# Run V1 map tests (Leaflet-based)
npx playwright test e2e/map/

# Run V2 map tests (MapLibre-based)
npx playwright test e2e/v2/map/

# Run specific test file
npx playwright test e2e/v2/map/settings.spec.js

# Run tests in headed mode (watch browser)
npx playwright test --headed

# Run tests in debug mode
npx playwright test --debug

# Run tests sequentially (avoid parallel issues)
npx playwright test --workers=1

# Run only non-destructive tests (safe for production data)
npx playwright test --grep-invert @destructive

# Run only destructive tests (use with caution!)
npx playwright test --grep @destructive
```

## Test Structure

```
e2e/
├── setup/           # Test setup and authentication
├── helpers/         # Shared helper functions
├── map/             # V1 Map tests (Leaflet) - 81 tests
├── v2/              # V2 Map tests (MapLibre) - 52 tests
│   ├── helpers/     # V2-specific helpers
│   ├── map/         # V2 core map tests
│   │   └── layers/  # V2 layer-specific tests
│   └── realtime/    # V2 real-time features
└── temp/            # Playwright artifacts (screenshots, videos)
```

## V1 Map Tests (Leaflet-based) - 81 tests

**Map Tests**
- `map-controls.spec.js` - Basic map controls, zoom, tile layers (5 tests)
- `map-layers.spec.js` - Layer toggles: Routes, Heatmap, Fog, etc. (8 tests)
- `map-points.spec.js` - Point interactions and deletion (4 tests, 1 destructive)
- `map-visits.spec.js` - Confirmed visit interactions and management (5 tests, 3 destructive)
- `map-suggested-visits.spec.js` - Suggested visit interactions (6 tests, 3 destructive)
- `map-add-visit.spec.js` - Add visit control and form (8 tests)
- `map-selection-tool.spec.js` - Selection tool functionality (4 tests)
- `map-calendar-panel.spec.js` - Calendar panel navigation (9 tests)
- `map-side-panel.spec.js` - Side panel (visits drawer) functionality (13 tests)*
- `map-bulk-delete.spec.js` - Bulk point deletion (12 tests, all destructive)
- `map-places-creation.spec.js` - Creating new places on map (9 tests, 2 destructive)
- `map-places-layers.spec.js` - Places layer visibility and filtering (10 tests)

\* Some side panel tests may be skipped if demo data doesn't contain visits

## V2 Map Tests (MapLibre-based) - 52 tests

**Organized by feature domain:**

### Core Map Tests
- `v2/map/core.spec.js` - Map initialization, lifecycle, loading states (8 tests)
- `v2/map/navigation.spec.js` - Zoom controls, date picker navigation (4 tests)
- `v2/map/interactions.spec.js` - Point clicks, hover effects, popups (2 tests)
- `v2/map/settings.spec.js` - Settings panel, layer toggles, persistence (10 tests)
- `v2/map/performance.spec.js` - Load time benchmarks, efficiency (2 tests)

### Layer Tests
- `v2/map/layers/points.spec.js` - Points display, GeoJSON data (3 tests)
- `v2/map/layers/routes.spec.js` - Routes geometry, styling, ordering (8 tests)
- `v2/map/layers/heatmap.spec.js` - Heatmap creation, toggle, persistence (3 tests)
- `v2/map/layers/visits.spec.js` - Visits layer toggle and display (2 tests)
- `v2/map/layers/photos.spec.js` - Photos layer toggle and display (2 tests)
- `v2/map/layers/areas.spec.js` - Areas layer toggle and display (2 tests)
- `v2/map/layers/advanced.spec.js` - Fog of war, scratch map (3 tests)

### Real-time Features
- `v2/realtime/family.spec.js` - Family tracking, ActionCable (2 tests, skipped)

### V2 Test Organization Benefits
- ✅ **Feature-based hierarchy** - Clear organization by domain
- ✅ **Zero duplication** - All settings tests consolidated
- ✅ **Easy to navigate** - Obvious file naming
- ✅ **Better maintainability** - One feature = one file

## Test Tags

Tests are tagged to enable selective execution:

- **@destructive** (22 tests in V1) - Tests that delete or modify data:
  - Bulk delete operations (12 tests)
  - Point deletion (1 test)
  - Visit modification/deletion (3 tests)
  - Suggested visit actions (3 tests)
  - Place creation (3 tests)

**Usage:**

```bash
# Safe for staging/production - run only non-destructive tests
npx playwright test --grep-invert @destructive

# Use with caution - run only destructive tests
npx playwright test --grep @destructive

# Run specific destructive test file
npx playwright test e2e/map/map-bulk-delete.spec.js
```

## Helper Functions

### V1 Map Helpers (`helpers/map.js`)
- `waitForMap(page)` - Wait for Leaflet map initialization
- `enableLayer(page, layerName)` - Enable a map layer by name
- `clickConfirmedVisit(page)` - Click first confirmed visit circle
- `clickSuggestedVisit(page)` - Click first suggested visit circle
- `getMapZoom(page)` - Get current map zoom level

### V2 Map Helpers (`v2/helpers/setup.js`)
- `navigateToMapsV2(page)` - Navigate to MapLibre map
- `navigateToMapsV2WithDate(page, startDate, endDate)` - Navigate with date range
- `waitForMapLibre(page)` - Wait for MapLibre initialization
- `waitForLoadingComplete(page)` - Wait for data loading
- `hasMapInstance(page)` - Check if map is initialized
- `getMapZoom(page)` - Get current zoom level
- `getMapCenter(page)` - Get map center coordinates
- `hasLayer(page, layerId)` - Check if layer exists
- `getLayerVisibility(page, layerId)` - Get layer visibility state
- `getPointsSourceData(page)` - Get points source data
- `getRoutesSourceData(page)` - Get routes source data
- `clickMapAt(page, x, y)` - Click at specific coordinates
- `hasPopup(page)` - Check if popup is visible

### Navigation Helpers (`helpers/navigation.js`)
- `closeOnboardingModal(page)` - Close getting started modal
- `navigateToDate(page, startDate, endDate)` - Navigate to specific date range
- `navigateToMap(page)` - Navigate to V1 map with setup

### Selection Helpers (`helpers/selection.js`)
- `drawSelectionRectangle(page, options)` - Draw selection on map
- `enableSelectionMode(page)` - Enable area selection tool

## Common Patterns

### V1 Basic Test Template (Leaflet)
```javascript
import { test, expect } from '@playwright/test';
import { navigateToMap } from '../helpers/navigation.js';
import { waitForMap } from '../helpers/map.js';

test('my test', async ({ page }) => {
  await navigateToMap(page);
  await waitForMap(page);
  // Your test logic
});
```

### V2 Basic Test Template (MapLibre)
```javascript
import { test, expect } from '@playwright/test';
import { closeOnboardingModal } from '../../helpers/navigation.js';
import {
  navigateToMapsV2,
  waitForMapLibre,
  waitForLoadingComplete
} from '../helpers/setup.js';

test.describe('My Feature', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page);
    await closeOnboardingModal(page);
    await waitForMapLibre(page);
    await waitForLoadingComplete(page);
  });

  test('my test', async ({ page }) => {
    // Your test logic
  });
});
```

### V2 Testing Layer Visibility
```javascript
import { getLayerVisibility } from '../helpers/setup.js';

// Check if layer is visible
const isVisible = await getLayerVisibility(page, 'points');
expect(isVisible).toBe(true);

// Wait for layer to exist
await page.waitForFunction(() => {
  const element = document.querySelector('[data-controller*="maps--maplibre"]');
  const app = window.Stimulus || window.Application;
  const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre');
  return controller?.map?.getLayer('routes') !== undefined;
}, { timeout: 5000 });
```

### V2 Testing Settings Panel
```javascript
// Open settings
await page.click('button[title="Open map settings"]');
await page.waitForTimeout(400);

// Switch to layers tab
await page.click('button[data-tab="layers"]');
await page.waitForTimeout(300);

// Check toggle state
const toggle = page.locator('label:has-text("Points")').first().locator('input.toggle');
const isChecked = await toggle.isChecked();
```

## Debugging

### View Test Artifacts
```bash
# Open HTML report
npx playwright show-report

# Screenshots and videos are in:
test-results/
```

### Common Issues

#### V1 Tests
- **Flaky tests**: Run with `--workers=1` to avoid parallel interference
- **Timeout errors**: Increase timeout in test or use `page.waitForTimeout()`
- **Map not loading**: Ensure `waitForMap()` is called after navigation

#### V2 Tests
- **Layer not ready**: Use `page.waitForFunction()` to wait for layer existence
- **Settings panel timing**: Add `waitForTimeout()` after opening/closing
- **Parallel test failures**: Some tests pass individually but fail in parallel - run with `--workers=3` or `--workers=1`
- **Source data not available**: Wait for source to be defined before accessing data

### V2 Test Tips
1. Always wait for MapLibre to initialize with `waitForMapLibre(page)`
2. Wait for data loading with `waitForLoadingComplete(page)`
3. Add layer existence checks before testing layer properties
4. Use proper waits for settings panel animations
5. Consider timing when testing layer toggles

## CI/CD

Tests run with:
- 1 worker (sequential)
- 2 retries on failure
- Screenshots/videos on failure
- JUnit XML reports

See `playwright.config.js` for full configuration.

## Important Considerations

- We're using Rails 8 with Turbo, which might not cause full page reloads
- V2 map uses MapLibre GL JS with Stimulus controllers
- V2 settings are persisted to localStorage
- V2 layer visibility is based on user settings (no hardcoded defaults)
- Some V2 layers (routes, heatmap) are created dynamically based on data

## Test Migration Notes

V2 tests were refactored from phase-based to feature-based organization:
- **Before**: 9 phase files, 96 tests (many duplicates)
- **After**: 13 feature files, 52 focused tests (zero duplication)
- **Code reduction**: 56% (2,314 lines → 1,018 lines)
- **Pass rate**: 94% (49/52 tests passing, 1 flaky, 2 skipped)

See `E2E_REFACTORING_SUCCESS.md` for complete migration details.
