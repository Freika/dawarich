# Layer Control Upgrade - Testing Checklist

## Pre-Testing Setup

1. **Start the development server**
   ```bash
   bin/dev
   ```

2. **Clear browser cache** to ensure new JavaScript and CSS are loaded

3. **Log in** to the application with demo credentials or your account

4. **Navigate to the Map page** (`/map`)

## Visual Verification

- [ ] Layer control appears in the top-right corner
- [ ] Layer control shows a hierarchical tree structure (not flat list)
- [ ] Control has two main sections: "Map Styles" and "Layers"
- [ ] Sections can be expanded/collapsed
- [ ] No standalone Places control button (📍) is visible

## Map Styles Testing

- [ ] Expand "Map Styles" section
- [ ] All map styles are listed (OpenStreetMap, OpenStreetMap.HOT, etc.)
- [ ] Selecting a different style changes the base map
- [ ] Only one map style can be selected at a time
- [ ] Selected style is indicated with a radio button

## Layers Testing

### Basic Layers
- [ ] Expand "Layers" section
- [ ] All basic layers are present:
  - [ ] Points
  - [ ] Routes
  - [ ] Tracks
  - [ ] Heatmap
  - [ ] Fog of War
  - [ ] Scratch map
  - [ ] Areas
  - [ ] Photos

- [ ] Toggle each layer on/off
- [ ] Verify each layer displays correctly when enabled
- [ ] Multiple layers can be enabled simultaneously

### Visits Group
- [ ] Expand "Visits" section
- [ ] Two sub-layers are present:
  - [ ] Suggested
  - [ ] Confirmed
- [ ] Enable "Suggested" - suggested visits appear on map
- [ ] Enable "Confirmed" - confirmed visits appear on map
- [ ] Disable both - no visits visible on map
- [ ] Select All checkbox works for Visits group

### Places Group
- [ ] Expand "Places" section
- [ ] At least these options are present:
  - [ ] Places (top-level checkbox)
  - [ ] Untagged
  - [ ] (Individual tags if any exist)

**Testing "Places (top-level checkbox)":**
- [ ] Enable "Places (top-level checkbox)"
- [ ] All places appear on map regardless of tags
- [ ] Place markers are clickable
- [ ] Place popups show correct information

**Testing "Untagged":**
- [ ] Enable "Untagged" (disable "Places (top-level checkbox)" first)
- [ ] Only places without tags appear
- [ ] Verify by checking places that have tags don't appear

**Testing Individual Tags:**
(If you have tags created)
- [ ] Each tag appears as a separate layer
- [ ] Tag icon is displayed before tag name
- [ ] Enable a tag layer
- [ ] Only places with that tag appear
- [ ] Multiple tag layers can be enabled simultaneously
- [ ] Select All checkbox works for Places group

### Family Members (if applicable)
- [ ] If in a family, "Family Members" layer appears
- [ ] Enable Family Members layer
- [ ] Family member locations appear on map
- [ ] Family member markers are distinguishable from own markers

## Functional Testing

### Layer Persistence
- [ ] Enable several layers (e.g., Points, Routes, Suggested Visits, Places (top-level checkbox))
- [ ] Refresh the page
- [ ] Verify enabled layers remain enabled after refresh
- [ ] Verify disabled layers remain disabled after refresh

### Places API Integration
- [ ] Open browser console (F12)
- [ ] Enable "Network" tab
- [ ] Enable "Untagged" places layer
- [ ] Verify API call: `GET /api/v1/places?api_key=...&untagged=true`
- [ ] Enable a tag layer
- [ ] Verify API call: `GET /api/v1/places?api_key=...&tag_ids=<tag_id>`
- [ ] Verify no JavaScript errors in console

### Layer Interaction
- [ ] Enable Routes layer
- [ ] Click on a route segment
- [ ] Verify route details popup appears
- [ ] Enable Places "Places (top-level checkbox)" layer
- [ ] Click on a place marker
- [ ] Verify place details popup appears
- [ ] Verify layers don't interfere with each other

### Performance
- [ ] Enable all layers simultaneously
- [ ] Map remains responsive
- [ ] No significant lag when toggling layers
- [ ] No memory leaks (check browser dev tools)

## Edge Cases

### No Tags Scenario
- [ ] If no tags exist, Places section should show:
  - [ ] Places (top-level checkbox)
  - [ ] Untagged
- [ ] No error in console

### No Places Scenario
- [ ] Disable all place layers
- [ ] Enable "Untagged"
- [ ] Verify appropriate message or empty state
- [ ] No errors in console

### No Family Scenario
- [ ] If not in a family, "Family Members" layer shouldn't appear
- [ ] No errors in console

## Regression Testing

### Existing Functionality
- [ ] Routes/Tracks selector still works (if visible with `tracks_debug=true`)
- [ ] Settings panel still works
- [ ] Calendar panel still works
- [ ] Visit selection tool still works
- [ ] Add visit button still works

### Other Controllers
- [ ] Family members controller still works (if applicable)
- [ ] Photo markers still load correctly
- [ ] Area drawing still works
- [ ] Fog of war updates correctly

## Mobile Testing (if applicable)

- [ ] Layer control is accessible on mobile
- [ ] Tree structure expands/collapses on tap
- [ ] Layers can be toggled on mobile
- [ ] No layout issues on small screens

## Error Scenarios

- [ ] Disconnect internet, try to load a layer that requires API call
- [ ] Verify appropriate error handling
- [ ] Verify user gets feedback about the failure
- [ ] Verify app doesn't crash

## Console Checks

Throughout all testing, monitor the browser console for:
- [ ] No JavaScript errors
- [ ] No unexpected warnings
- [ ] No failed API requests (except during error scenario testing)
- [ ] Appropriate log messages for debugging

## Sign-off

- [ ] All critical tests pass
- [ ] Any failures are documented
- [ ] Ready for production deployment

---

## Notes

Record any issues, unexpected behavior, or suggestions for improvement:

```
[Your notes here]
```
