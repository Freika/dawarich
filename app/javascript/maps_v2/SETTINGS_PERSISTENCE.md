# Maps V2 Settings Persistence

Maps V2 persists user settings across sessions and devices using a hybrid approach with backend API storage and localStorage fallback. **Settings are shared with Maps V1** for seamless migration.

## Architecture

### Dual Storage Strategy

1. **Primary: Backend API** (`/api/v1/settings`)
   - Settings stored in User's `settings` JSONB column
   - Syncs across all devices/browsers
   - Requires authentication via API key
   - **Compatible with v1 map settings**

2. **Fallback: localStorage**
   - Instant save/load without network
   - Browser-specific storage
   - Used when backend unavailable

## Settings Stored

Maps V2 shares layer visibility settings with v1 using the `enabled_map_layers` array:

| Frontend Setting | Backend Key | Type | Default |
|-----------------|-------------|------|---------|
| `mapStyle` | `maps_v2_style` | string | `'light'` |
| `enabledMapLayers` | `enabled_map_layers` | array | `['Points', 'Routes']` |

### Layer Names

The `enabled_map_layers` array contains layer names as strings:
- `'Points'` - Individual location points
- `'Routes'` - Connected route lines
- `'Heatmap'` - Density heatmap
- `'Visits'` - Detected area visits
- `'Photos'` - Geotagged photos
- `'Areas'` - Defined areas
- `'Tracks'` - Saved tracks
- `'Fog of War'` - Explored areas
- `'Scratch map'` - Scratched countries

Internally, v2 converts these to boolean flags (e.g., `pointsVisible`, `routesVisible`) for easier state management, but always saves back to the shared array format.

## How It Works

### Initialization Flow

```
1. User opens Maps V2
   ↓
2. SettingsManager.initialize(apiKey)
   ↓
3. SettingsManager.sync()
   ↓
4. Load from backend API
   ↓
5. Merge with defaults
   ↓
6. Save to localStorage (cache)
   ↓
7. Return merged settings
```

### Update Flow

```
User toggles Heatmap layer
   ↓
SettingsManager.updateSetting('heatmapEnabled', true)
   ↓
Convert booleans → array: ['Points', 'Routes', 'Heatmap']
   ↓
┌──────────────────┬──────────────────┐
│ Save to          │ Save to          │
│ localStorage     │ Backend API      │
│ (instant)        │ (async)          │
└──────────────────┴──────────────────┘
   ↓                      ↓
UI updates          Backend stores:
immediately         { enabled_map_layers: [...] }
```

### Format Conversion

v2 internally uses boolean flags for state management but saves/loads using v1's array format:

**Loading (Array → Booleans)**:
```javascript
// Backend returns
{ enabled_map_layers: ['Points', 'Routes', 'Heatmap'] }

// Converted to
{
  pointsVisible: true,
  routesVisible: true,
  heatmapEnabled: true,
  visitsEnabled: false,
  // ... etc
}
```

**Saving (Booleans → Array)**:
```javascript
// v2 state
{
  pointsVisible: true,
  routesVisible: false,
  heatmapEnabled: true
}

// Saved as
{ enabled_map_layers: ['Points', 'Heatmap'] }
```

## API Integration

### Backend Endpoints

**GET `/api/v1/settings`**
```javascript
// Request
Headers: {
  'Authorization': 'Bearer <api_key>'
}

// Response
{
  "settings": {
    "maps_v2_style": "dark",
    "maps_v2_heatmap": true,
    // ... other settings
  },
  "status": "success"
}
```

**PATCH `/api/v1/settings`**
```javascript
// Request
Headers: {
  'Authorization': 'Bearer <api_key>',
  'Content-Type': 'application/json'
}
Body: {
  "settings": {
    "maps_v2_style": "dark",
    "maps_v2_heatmap": true
  }
}

// Response
{
  "message": "Settings updated",
  "settings": { /* updated settings */ },
  "status": "success"
}
```

## Usage Examples

### Basic Usage

```javascript
import { SettingsManager } from 'maps_v2/utils/settings_manager'

// Initialize with API key (done in controller)
SettingsManager.initialize(apiKey)

// Sync settings from backend on app load
const settings = await SettingsManager.sync()

// Get specific setting
const mapStyle = SettingsManager.getSetting('mapStyle')

// Update setting (saves to both localStorage and backend)
await SettingsManager.updateSetting('mapStyle', 'dark')

// Reset to defaults
SettingsManager.resetToDefaults()
```

### In Controller

```javascript
export default class extends Controller {
  static values = { apiKey: String }

  async connect() {
    // Initialize settings manager
    SettingsManager.initialize(this.apiKeyValue)

    // Load settings (syncs from backend)
    this.settings = await SettingsManager.sync()

    // Use settings
    const style = await getMapStyle(this.settings.mapStyle)
    this.map = new maplibregl.Map({ style })
  }

  updateMapStyle(event) {
    const style = event.target.value
    // Automatically saves to both localStorage and backend
    SettingsManager.updateSetting('mapStyle', style)
  }
}
```

## Error Handling

The settings manager handles errors gracefully:

1. **Backend unavailable**: Falls back to localStorage
2. **localStorage full**: Logs error, uses defaults
3. **Invalid settings**: Merges with defaults
4. **Network errors**: Non-blocking, localStorage still updated

```javascript
// Example: Backend fails, but localStorage succeeds
SettingsManager.updateSetting('mapStyle', 'dark')
// → UI updates immediately (localStorage)
// → Backend save fails silently (logged to console)
// → User experience not interrupted
```

## Benefits

### Cross-Device Sync
Settings automatically sync when user logs in from different devices:
```
User enables heatmap on Desktop
   ↓
Backend stores setting
   ↓
User opens app on Mobile
   ↓
Settings sync from backend
   ↓
Heatmap enabled on Mobile too
```

### Offline Support
Works without internet connection:
```
User offline
   ↓
Settings load from localStorage
   ↓
User changes settings
   ↓
Saves to localStorage only
   ↓
User goes online
   ↓
Next setting change syncs to backend
```

### Performance
- **Instant UI updates**: localStorage writes are synchronous
- **Non-blocking backend sync**: API calls don't freeze UI
- **Cached locally**: No network request on every page load

## Migration from localStorage-Only

Existing users with localStorage settings will seamlessly migrate:

```
1. Old user opens Maps V2
   ↓
2. Settings manager initializes
   ↓
3. Loads settings from localStorage
   ↓
4. Syncs with backend (first time)
   ↓
5. Backend stores localStorage settings
   ↓
6. Future sessions load from backend
```

## Database Schema

Settings stored in `users.settings` JSONB column:

```sql
-- Example user settings (shared between v1 and v2)
{
  "maps_v2_style": "dark",
  "enabled_map_layers": ["Points", "Routes", "Heatmap", "Visits"],
  // ... other settings shared by both versions
  "preferred_map_layer": "OpenStreetMap",
  "fog_of_war_meters": "100",
  "route_opacity": 60
}
```

## Testing

### Manual Testing

1. **Test Backend Sync**
   ```javascript
   // In browser console
   SettingsManager.updateSetting('mapStyle', 'dark')
   // Check Network tab for PATCH /api/v1/settings
   ```

2. **Test Cross-Device**
   - Change setting on Device A
   - Open Maps V2 on Device B
   - Verify setting is synced

3. **Test Offline**
   - Go offline (Network tab → Offline)
   - Change settings
   - Verify localStorage updated
   - Go online
   - Change another setting
   - Verify backend receives update

### Automated Testing (Future)

```ruby
# spec/requests/api/v1/settings_controller_spec.rb
RSpec.describe 'Maps V2 Settings' do
  it 'saves maps_v2 settings' do
    patch '/api/v1/settings',
      params: { settings: { maps_v2_style: 'dark' } },
      headers: auth_headers

    expect(user.reload.settings['maps_v2_style']).to eq('dark')
  end
end
```

## Troubleshooting

### Settings Not Syncing

**Check API key**:
```javascript
console.log('API key set:', SettingsManager.apiKey !== null)
```

**Check network requests**:
- Open DevTools → Network
- Filter for `/api/v1/settings`
- Verify PATCH requests after setting changes

**Check backend response**:
```javascript
// Enable verbose logging
SettingsManager.sync().then(console.log)
```

### Settings Reset After Reload

**Possible causes**:
1. Backend not saving (check server logs)
2. API key invalid/expired
3. localStorage disabled (private browsing)

**Solution**:
```javascript
// Clear and resync
localStorage.removeItem('dawarich-maps-v2-settings')
await SettingsManager.sync()
```

## Future Enhancements

Possible improvements:
1. **Settings versioning**: Migrate old setting formats
2. **Conflict resolution**: Handle concurrent updates
3. **Setting presets**: Save/load named presets
4. **Export/import**: Share settings between users
5. **Real-time sync**: WebSocket updates for multi-tab support
