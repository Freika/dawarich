# E2E Tests

End-to-end tests for Dawarich using Playwright.

## Running Tests

```bash
# Run all tests
npx playwright test

# Run specific test file
npx playwright test e2e/map/map-controls.spec.js

# Run tests in headed mode (watch browser)
npx playwright test --headed

# Run tests in debug mode
npx playwright test --debug

# Run tests sequentially (avoid parallel issues)
npx playwright test --workers=1
```

## Structure

```
e2e/
├── setup/           # Test setup and authentication
├── helpers/         # Shared helper functions
├── map/             # Map-related tests (40 tests total)
└── temp/            # Playwright artifacts (screenshots, videos)
```

### Test Files

**Map Tests (62 tests)**
- `map-controls.spec.js` - Basic map controls, zoom, tile layers (5 tests)
- `map-layers.spec.js` - Layer toggles: Routes, Heatmap, Fog, etc. (8 tests)
- `map-points.spec.js` - Point interactions and deletion (4 tests)
- `map-visits.spec.js` - Confirmed visit interactions and management (5 tests)
- `map-suggested-visits.spec.js` - Suggested visit interactions (confirm/decline) (6 tests)
- `map-add-visit.spec.js` - Add visit control and form (8 tests)
- `map-selection-tool.spec.js` - Selection tool functionality (4 tests)
- `map-calendar-panel.spec.js` - Calendar panel navigation (9 tests)
- `map-side-panel.spec.js` - Side panel (visits drawer) functionality (13 tests)*
- `map-bulk-delete.spec.js` - Bulk point deletion (12 tests)

\* Some side panel tests may be skipped if demo data doesn't contain visits

## Helper Functions

### Map Helpers (`helpers/map.js`)
- `waitForMap(page)` - Wait for Leaflet map initialization
- `enableLayer(page, layerName)` - Enable a map layer by name
- `clickConfirmedVisit(page)` - Click first confirmed visit circle
- `clickSuggestedVisit(page)` - Click first suggested visit circle
- `getMapZoom(page)` - Get current map zoom level

### Navigation Helpers (`helpers/navigation.js`)
- `closeOnboardingModal(page)` - Close getting started modal
- `navigateToDate(page, startDate, endDate)` - Navigate to specific date range
- `navigateToMap(page)` - Navigate to map page with setup

### Selection Helpers (`helpers/selection.js`)
- `drawSelectionRectangle(page, options)` - Draw selection on map
- `enableSelectionMode(page)` - Enable area selection tool

## Common Patterns

### Basic Test Template
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

### Testing Map Layers
```javascript
import { enableLayer } from '../helpers/map.js';

await enableLayer(page, 'Routes');
await enableLayer(page, 'Heatmap');
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
- **Flaky tests**: Run with `--workers=1` to avoid parallel interference
- **Timeout errors**: Increase timeout in test or use `page.waitForTimeout()`
- **Map not loading**: Ensure `waitForMap()` is called after navigation

## CI/CD

Tests run with:
- 1 worker (sequential)
- 2 retries on failure
- Screenshots/videos on failure
- JUnit XML reports

See `playwright.config.js` for full configuration.
