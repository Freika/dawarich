# Dawarich E2E Test Suite

This directory contains comprehensive end-to-end tests for the Dawarich location tracking application using Playwright.

## Test Structure

The test suite is organized into several test files that cover different aspects of the application:

### Core Test Files

- **`auth.spec.ts`** - Authentication and user management tests
- **`map.spec.ts`** - Map functionality and visualization tests
- **`imports.spec.ts`** - Data import functionality tests
- **`settings.spec.ts`** - Application settings and configuration tests
- **`navigation.spec.ts`** - Navigation and UI interaction tests
- **`trips.spec.ts`** - Trip management and analysis tests

### Helper Files

- **`fixtures/test-helpers.ts`** - Reusable test utilities and helper functions
- **`global-setup.ts`** - Global test environment setup
- **`example.spec.ts`** - Basic example test (can be removed)

## Configuration

- **`playwright.config.ts`** - Playwright configuration with browser setup, timeouts, and test settings

## Getting Started

### Prerequisites

1. Node.js and npm installed
2. Dawarich application running locally on port 3000 (or configured port)
3. Test environment properly configured

### Installation

```bash
# Install Playwright
npm install -D @playwright/test

# Install browsers (first time only)
npx playwright install
```

### Running Tests

```bash
# Run all tests
npm run test:e2e

# Run tests in headed mode (see browser)
npx playwright test --headed

# Run specific test file
npx playwright test auth.spec.ts

# Run tests with specific browser
npx playwright test --project=chromium

# Run tests in debug mode
npx playwright test --debug
```

### Test Reports

```bash
# Generate HTML report
npx playwright show-report

# View last test results
npx playwright show-report
```

## Test Coverage

### High Priority Features (✅ Covered)
- User authentication (login/logout)
- Map visualization and interaction
- Data import from various sources
- Basic settings configuration
- Navigation and UI interactions
- Trip management and creation

### Medium Priority Features (✅ Covered)
- Settings management (integrations, map config)
- Mobile responsive behavior
- Data visualization and statistics
- File upload handling
- User preferences and customization

### Low Priority Features (✅ Covered)
- Advanced trip analysis
- Performance testing
- Error handling
- Accessibility testing
- Keyboard navigation

## Test Patterns

### Helper Functions

Use the `TestHelpers` class for common operations:

```typescript
import { TestHelpers } from './fixtures/test-helpers';

test('example', async ({ page }) => {
  const helpers = new TestHelpers(page);
  await helpers.loginAsDemo();
  await helpers.navigateTo('Map');
  await helpers.waitForMap();
});
```

### Test Organization

Tests are organized with descriptive `test.describe` blocks:

```typescript
test.describe('Feature Name', () => {
  test.describe('Sub-feature', () => {
    test('should do something specific', async ({ page }) => {
      // Test implementation
    });
  });
});
```

### Assertions

Use clear, descriptive assertions:

```typescript
// Good
await expect(page.getByRole('heading', { name: 'Map' })).toBeVisible();

// Better with context
await expect(page.getByRole('button', { name: 'Create Trip' })).toBeVisible();
```

## Configuration Notes

### Environment Variables

The tests use these environment variables:

- `BASE_URL` - Base URL for the application (defaults to http://localhost:3000)
- `CI` - Set to true in CI environments

### Test Data

Tests use the demo user credentials:
- Email: `demo@dawarich.app`
- Password: `password`

### Browser Configuration

Tests run on:
- Chromium (primary)
- Firefox
- WebKit (Safari)
- Mobile Chrome
- Mobile Safari

## Best Practices

### 1. Test Independence

Each test should be independent and able to run in isolation:

```typescript
test.beforeEach(async ({ page }) => {
  const helpers = new TestHelpers(page);
  await helpers.loginAsDemo();
});
```

### 2. Robust Selectors

Use semantic selectors that won't break easily:

```typescript
// Good
await page.getByRole('button', { name: 'Save' });
await page.getByLabel('Email');

// Avoid
await page.locator('.btn-primary');
await page.locator('#email-input');
```

### 3. Wait for Conditions

Wait for specific conditions rather than arbitrary timeouts:

```typescript
// Good
await page.waitForLoadState('networkidle');
await expect(page.getByText('Success')).toBeVisible();

// Avoid
await page.waitForTimeout(5000);
```

### 4. Handle Optional Elements

Use conditional logic for elements that may not exist:

```typescript
const deleteButton = page.getByRole('button', { name: 'Delete' });
if (await deleteButton.isVisible()) {
  await deleteButton.click();
}
```

### 5. Mobile Testing

Include mobile viewport testing:

```typescript
test('should work on mobile', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 667 });
  // Test implementation
});
```

## Maintenance

### Adding New Tests

1. Create tests in the appropriate spec file
2. Use descriptive test names
3. Follow the existing patterns
4. Update this README if adding new test files

### Updating Selectors

When the application UI changes:
1. Update selectors in helper functions first
2. Run tests to identify breaking changes
3. Update individual test files as needed

### Performance Considerations

- Tests include performance checks for critical paths
- Map loading times are monitored
- Navigation speed is tested
- Large dataset handling is verified

## Debugging

### Common Issues

1. **Server not ready** - Ensure Dawarich is running on the correct port
2. **Element not found** - Check if UI has changed or element is conditionally rendered
3. **Timeouts** - Verify network conditions and increase timeouts if needed
4. **Map not loading** - Ensure map dependencies are available

### Debug Tips

```bash
# Run with debug flag
npx playwright test --debug

# Run specific test with trace
npx playwright test auth.spec.ts --trace on

# Record video on failure
npx playwright test --video retain-on-failure
```

## CI/CD Integration

The test suite is configured for CI/CD with:
- Automatic retry on failure
- Parallel execution control
- Artifact collection (screenshots, videos, traces)
- HTML report generation

## Contributing

When adding new tests:
1. Follow the existing patterns
2. Add appropriate test coverage
3. Update documentation
4. Ensure tests pass in all browsers
5. Consider mobile and accessibility aspects

## Support

For issues with the test suite:
1. Check the test logs and reports
2. Verify application state
3. Review recent changes
4. Check browser compatibility
