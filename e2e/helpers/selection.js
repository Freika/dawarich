/**
 * Selection and drawing helper functions for Playwright tests
 */

/**
 * Enable selection mode by clicking the selection tool button
 * @param {Page} page - Playwright page object
 */
export async function enableSelectionMode(page) {
  const selectionButton = page.locator('#selection-tool-button');
  await selectionButton.click();
  await page.waitForTimeout(500);
}

/**
 * Draw a selection rectangle on the map
 * @param {Page} page - Playwright page object
 * @param {Object} options - Drawing options
 * @param {number} options.startX - Start X position (0-1 as fraction of width, default: 0.2)
 * @param {number} options.startY - Start Y position (0-1 as fraction of height, default: 0.2)
 * @param {number} options.endX - End X position (0-1 as fraction of width, default: 0.8)
 * @param {number} options.endY - End Y position (0-1 as fraction of height, default: 0.8)
 * @param {number} options.steps - Number of steps for smooth drag (default: 10)
 */
export async function drawSelectionRectangle(page, options = {}) {
  const {
    startX = 0.2,
    startY = 0.2,
    endX = 0.8,
    endY = 0.8,
    steps = 10
  } = options;

  // Click area selection tool
  const selectionButton = page.locator('#selection-tool-button');
  await selectionButton.click();
  await page.waitForTimeout(500);

  // Get map container bounding box
  const mapContainer = page.locator('#map [data-maps-target="container"]');
  const bbox = await mapContainer.boundingBox();

  // Calculate absolute positions
  const absStartX = bbox.x + bbox.width * startX;
  const absStartY = bbox.y + bbox.height * startY;
  const absEndX = bbox.x + bbox.width * endX;
  const absEndY = bbox.y + bbox.height * endY;

  // Draw rectangle
  await page.mouse.move(absStartX, absStartY);
  await page.mouse.down();
  await page.mouse.move(absEndX, absEndY, { steps });
  await page.mouse.up();

  // Wait for API calls and drawer animations
  await page.waitForTimeout(2000);

  // Wait for drawer to open (it should open automatically after selection)
  await page.waitForSelector('#visits-drawer.open', { timeout: 15000 });

  // Wait for delete button to appear in the drawer (indicates selection is complete)
  await page.waitForSelector('#delete-selection-button', { timeout: 15000 });
  await page.waitForTimeout(500); // Brief wait for UI to stabilize
}
