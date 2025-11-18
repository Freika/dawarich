# Layer Control Upgrade - Leaflet.Control.Layers.Tree

## Summary

Successfully installed and integrated the `Leaflet.Control.Layers.Tree` plugin to replace the standard Leaflet layer control with a hierarchical tree-based control that better organizes map layers and styles.

## Changes Made

### 1. Installation

- **Plugin**: Installed `leaflet.control.layers.tree` via importmap
- **CSS**: Added plugin CSS file at `app/assets/stylesheets/leaflet.control.layers.tree.css`

### 2. Maps Controller Updates

#### File: `app/javascript/controllers/maps_controller.js`

**Import Changes:**
- Added import for `leaflet.control.layers.tree`
- Removed import for `createPlacesControl` (now integrated into tree control)

**Initialization Changes:**
- Removed standalone Places control initialization
- Added `this.userTags` property to store user tags for places filtering
- Updated layer control initialization to use `createTreeLayerControl()`

**New Methods:**

1. **`createTreeLayerControl(additionalLayers = {})`**
   - Creates a hierarchical tree structure for map layers
   - Organizes layers into two main groups:
     - **Map Styles**: All available base map layers
     - **Layers**: All overlay layers with nested groups
   - Supports dynamic additional layers (e.g., Family Members)

   Structure:
   ```
   + Map Styles
     - OpenStreetMap
     - OpenStreetMap.HOT
     - ...
   + Layers
     - Points
     - Routes
     - Tracks
     - Heatmap
     - Fog of War
     - Scratch map
     - Areas
     - Photos
     + Visits
       - Suggested
       - Confirmed
     + Places
       - All
       - Untagged
       - (each tag with icon)
   ```

**Updated Methods:**
- **`updateLayerControl()`**: Simplified to just recreate the tree control with additional layers
- Updated all layer control recreations throughout the file to use `createTreeLayerControl()`

### 3. Places Manager Updates

#### File: `app/javascript/maps/places.js`

**New Methods:**

1. **`createFilteredLayer(tagIds)`**
   - Creates a layer group for filtered places
   - Returns a layer that loads places when added to the map
   - Supports tag-based and untagged filtering

2. **`loadPlacesIntoLayer(layer, tagIds)`**
   - Loads places into a specific layer with tag filtering
   - Handles API calls with tag_ids or untagged parameters
   - Creates markers using existing `createPlaceMarker()` method

## Features

### Hierarchical Organization
- Map styles and layers are now clearly separated
- Related layers are grouped together (Visits, Places)
- Easy to expand/collapse sections

### Places Layer Integration
- No longer needs a separate control
- All places filters are now in the tree control
- Each tag gets its own layer in the tree
- Places group has "All", "Untagged", and individual tag layers regardless of tags
- "Untagged" shows only places without tags

### Dynamic Layer Support
- Family Members layer can be added dynamically
- Additional layers can be easily integrated
- Maintains compatibility with existing layer management

### Improved User Experience
- Cleaner UI with collapsible sections
- Better organization of many layers
- Consistent interface for all layer types
- Select All checkbox for grouped layers (Visits, Places)

## API Changes

### Places API
The Places API now supports an `untagged` parameter:
- `GET /api/v1/places?untagged=true` - Returns only untagged places
- `GET /api/v1/places?tag_ids=1,2,3` - Returns places with specified tags

## Testing Recommendations

1. **Basic Functionality**
   - Verify all map styles load correctly
   - Test all overlay layers (Points, Routes, Tracks, etc.)
   - Confirm layer visibility persists correctly

2. **Places Integration**
   - Test "All" layer shows all places
   - Verify "Untagged" layer shows only untagged places
   - Test individual tag layers show correct places
   - Confirm places load when layer is enabled

3. **Visits Integration**
   - Test Suggested and Confirmed visits layers
   - Verify visits load correctly when enabled

4. **Family Members**
   - Test Family Members layer appears when family is available
   - Verify layer updates when family locations change

5. **Layer State Persistence**
   - Verify enabled layers are saved to user settings
   - Confirm layer state is restored on page load

## Migration Notes

### Removed Components
- Standalone Places control button (📍)
- `createPlacesControl` function no longer used in maps_controller

### Behavioral Changes
- Places layer is no longer managed by a separate control
- All places filtering is now done through the layer control
- Places markers are created on-demand when layer is enabled

## Future Enhancements

1. **Layer Icons**: Add custom icons for each layer type
2. **Layer Counts**: Show number of items in each layer
3. **Custom Styling**: Theme the tree control to match app theme
4. **Layer Search**: Add search functionality for finding layers
5. **Layer Presets**: Allow saving custom layer combinations

## Files Modified

1. `app/javascript/controllers/maps_controller.js` - Main map controller
2. `app/javascript/maps/places.js` - Places manager with new filtering methods
3. `config/importmap.rb` - Added tree control import (via bin/importmap)
4. `app/assets/stylesheets/leaflet.control.layers.tree.css` - Plugin CSS

## Rollback Plan

If needed, to rollback:
1. Remove `import "leaflet.control.layers.tree"` from maps_controller.js
2. Restore `import { createPlacesControl }` from places_control
3. Revert `createTreeLayerControl()` to `L.control.layers()`
4. Restore Places control initialization
5. Remove `leaflet.control.layers.tree` from importmap
6. Remove CSS file
