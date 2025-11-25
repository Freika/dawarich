# Maps V2 Settings Persistence

Maps V2 now persists user settings across sessions and devices using a hybrid approach with backend API storage and localStorage fallback.

## Architecture

### Dual Storage Strategy

1. **Primary: Backend API** (`/api/v1/settings`)
   - Settings stored in User's `settings` JSONB column
   - Syncs across all devices/browsers
   - Requires authentication via API key

2. **Fallback: localStorage**
   - Instant save/load without network
   - Browser-specific storage
   - Used when backend unavailable

## Settings Stored

All Maps V2 user preferences are persisted:

| Frontend Setting | Backend Key | Type | Default |
|-----------------|-------------|------|---------|
| `mapStyle` | `maps_v2_style` | string | `'light'` |
| `clustering` | `maps_v2_clustering` | boolean | `true` |
| `clusterRadius` | `maps_v2_cluster_radius` | number | `50` |
| `heatmapEnabled` | `maps_v2_heatmap` | boolean | `false` |
| `pointsVisible` | `maps_v2_points` | boolean | `true` |
| `routesVisible` | `maps_v2_routes` | boolean | `true` |
| `visitsEnabled` | `maps_v2_visits` | boolean | `false` |
| `photosEnabled` | `maps_v2_photos` | boolean | `false` |
| `areasEnabled` | `maps_v2_areas` | boolean | `false` |
| `tracksEnabled` | `maps_v2_tracks` | boolean | `false` |
| `fogEnabled` | `maps_v2_fog` | boolean | `false` |
| `scratchEnabled` | `maps_v2_scratch` | boolean | `false` |

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
User changes setting (e.g., enables heatmap)
   ↓
SettingsManager.updateSetting('heatmapEnabled', true)
   ↓
┌──────────────────┬──────────────────┐
│ Save to          │ Save to          │
│ localStorage     │ Backend API      │
│ (instant)        │ (async)          │
└──────────────────┴──────────────────┘
   ↓                      ↓
UI updates          Backend stores
immediately         (non-blocking)
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
-- Example user settings
{
  "maps_v2_style": "dark",
  "maps_v2_heatmap": true,
  "maps_v2_clustering": true,
  "maps_v2_cluster_radius": 50,
  // ... other Maps V2 settings
  // ... Maps V1 settings (coexist)
  "preferred_map_layer": "Light",
  "enabled_map_layers": ["Routes", "Heatmap"]
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
