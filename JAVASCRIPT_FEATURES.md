# Dawarich JavaScript Features Documentation

This document provides a detailed overview of all JavaScript features implemented in the Dawarich application, organized by functionality.

## Table of Contents

- [Map Features](#map-features)
- [Routes & Tracks](#routes--tracks)
- [Visits Management](#visits-management)
- [Areas](#areas)
- [Photos Integration](#photos-integration)
- [Live Mode](#live-mode)
- [Visualization Features](#visualization-features)
- [Search & Navigation](#search--navigation)
- [Family Sharing](#family-sharing)
- [Controllers](#controllers)

---

## Map Features

### Main Maps Controller (`maps_controller.js`)

The primary controller managing all map interactions and visualizations.

#### Core Functionality

- **Map Initialization**
  - Leaflet.js-based interactive map
  - Multiple base layer support (OpenStreetMap, custom tiles)
  - User-preferred layer persistence
  - PostGIS coordinate system support
  - Custom panes for z-index management

- **Layer Management**
  - Points layer (location markers)
  - Routes layer (polylines)
  - Tracks layer (GPS tracks)
  - Heatmap layer
  - Fog of War layer
  - Scratch map layer (visited countries)
  - Areas layer (user-defined regions)
  - Photos layer (geotagged images)
  - Visits layer (detected location visits)
  - Family members layer

- **Settings Panel**
  - Route opacity adjustment (10-100%)
  - Fog of War radius customization
  - Time/distance thresholds for route splitting
  - Points rendering mode (raw/simplified)
  - Live map toggle
  - Speed-colored routes configuration
  - Speed color scale editor with gradient stops

- **Calendar Panel**
  - Year selection dropdown
  - Month navigation grid
  - Tracked months visualization
  - Visited cities display
  - Date range filtering

- **Scale & Stats Control**
  - Distance scale (km/miles)
  - Total distance display
  - Points count display
  - Dynamic unit conversion

---

## Routes & Tracks

### Routes (`maps/polylines.js`)

#### Features

- **Intelligent Route Splitting**
  - Distance-based splitting (meters between points)
  - Time-based splitting (minutes between points)
  - Configurable thresholds

- **Speed Visualization**
  - Color-coded routes based on GPS velocity
  - Customizable color gradient scale
  - Speed ranges: 0-15 km/h (green), 15-30 km/h (cyan), 30-50 km/h (magenta), 50-100 km/h (yellow), 100+ km/h (red)
  - Real-time gradient editor

- **Interactive Features**
  - Hover highlighting with increased opacity
  - Click to lock selection
  - Start/end markers (🚥 and 🏁)
  - Popup with route details:
    - Start and end timestamps
    - Duration (days, hours, minutes)
    - Total distance
    - Current segment speed

- **Performance Optimizations**
  - Canvas renderer for large datasets
  - Batch processing for updates
  - Custom pane management (z-index 450)

### Tracks (`maps/tracks.js`)

GPS tracks represent processed and analyzed routes with elevation data.

#### Features

- **Track Visualization**
  - Distinct red color (vs blue routes)
  - Elevated pane (z-index 460)
  - Start (🚀) and end (🎯) markers

- **Track Information Display**
  - Start/end timestamps
  - Duration
  - Distance
  - Average speed
  - Elevation gain/loss
  - Max/min altitude

- **Real-time Updates**
  - WebSocket integration via TracksChannel
  - Incremental track updates (create/update/delete)
  - Time range filtering
  - Memory-efficient updates

---

## Visits Management

### Visits System (`maps/visits.js`)

Advanced location visit detection and management system.

#### Core Features

- **Visit Detection**
  - Automatic visit suggestions based on dwell time
  - Confirmed vs suggested visits (separate layers)
  - Custom panes for proper z-index ordering
  - Visual distinction (blue for confirmed, orange/dashed for suggested)

- **Area Selection Tool**
  - Click-and-drag rectangle selection
  - Filter visits within selected area
  - Points within bounds calculation
  - Date-grouped summary panel

- **Visit Drawer UI**
  - Sliding side panel
  - Hierarchical visit list
  - Visit status indicators
  - Quick actions (confirm/decline)

- **Visit Operations**
  - Confirm suggested visits
  - Decline unwanted visits
  - Merge multiple visits
  - Bulk operations (confirm/decline multiple)
  - Delete visits with confirmation
  - Edit visit name and location

- **Interactive Features**
  - Checkbox selection with smart visibility
  - Adjacent visit highlighting
  - Map circle highlighting on hover
  - Click visit to center map
  - Possible places dropdown
  - Duration formatting

- **Visit Details**
  - Name and address
  - Start and end timestamps
  - Duration estimation
  - Location coordinates
  - City, state, country
  - Status (suggested/confirmed/declined)

---

## Areas

### Area Management (`maps/areas.js`)

User-defined geographic areas for visit tracking.

#### Features

- **Area Creation**
  - Leaflet.draw integration
  - Circle drawing tool
  - Interactive popup form
  - Name input validation
  - Custom pane (z-index 605)

- **Area Display**
  - Red circle markers
  - Semi-transparent fill
  - Hover effects (increased opacity)
  - Click to show details

- **Area Information**
  - Name
  - Radius (meters)
  - Center coordinates
  - Area ID badge

- **Area Management**
  - Delete confirmation
  - Theme-aware styling
  - API integration for CRUD operations

---

## Photos Integration

### Photo Layer (`maps/photos.js`)

Integration with Immich and Photoprism for geotagged photos.

#### Features

- **Photo Sources**
  - Immich integration
  - Photoprism integration
  - Source URL configuration

- **Photo Markers**
  - 48x48px thumbnail markers
  - Lazy loading with retry logic
  - Loading spinner animation
  - Error handling

- **Photo Popups**
  - Full thumbnail preview
  - Original filename
  - Capture timestamp
  - Location (city, state, country)
  - Source system link
  - Type indicator (📷 photo / 🎥 video)
  - Hover shadow effects

- **Performance**
  - Promise-based loading
  - Progressive rendering
  - Automatic retry (3 attempts)
  - Date range filtering

---

## Live Mode

### Live Map Handler (`maps/live_map_handler.js`)

Real-time GPS tracking with memory-efficient streaming.

#### Features

- **Memory Management**
  - Bounded data structures (max 1000 points)
  - Automatic old point removal
  - Prevents memory leaks
  - Incremental updates

- **Real-time Updates**
  - WebSocket integration (PointsChannel)
  - Live marker addition
  - Incremental polyline segments
  - Heatmap updates
  - Auto-pan to new location

- **Layer Synchronization**
  - Markers layer updates
  - Polylines layer incremental updates
  - Heatmap point management
  - Fog of War updates

- **Performance**
  - No full layer recreation
  - Direct marker references
  - Efficient last marker tracking
  - Smart cleanup on disable

---

## Visualization Features

### Fog of War (`maps/fog_of_war.js`)

Gamification feature showing unexplored areas.

#### Features

- **Canvas-based Rendering**
  - Overlay at z-index 400
  - RGBA fog layer (0,0,0,0.4)
  - destination-out composite operation
  - Responsive to map size changes

- **Smart Fog Clearing**
  - Circular cleared areas around points
  - Line connections between nearby points
  - Configurable clear radius (meters)
  - Time threshold for connections
  - Rounded line caps and joins

- **Dynamic Updates**
  - Pan and zoom responsive
  - Real-time recalculation
  - Map resize handling
  - Stored parameters for efficiency

### Scratch Map (`maps/scratch_layer.js`)

World map showing visited countries.

#### Features

- **Country Visualization**
  - GeoJSON country borders
  - Golden overlay (fillColor: #FFD700)
  - Orange borders (color: #FFA500)
  - ISO 3166-1 Alpha-2 code matching

- **Data Management**
  - Country code mapping
  - Unique country extraction
  - Cached world borders data
  - Automatic refresh

- **Integration**
  - Layer control toggle
  - Marker data updates
  - Visibility state tracking

### Heatmap

Built-in Leaflet.heat plugin for density visualization.

- **Configuration**
  - 20px radius
  - 0.2 intensity per point
  - Automatic color gradient
  - Layer control toggle

---

## Search & Navigation

### Location Search (`maps/location_search.js`)

Advanced location search with visit history.

#### Features

- **Search Interface**
  - Inline search bar (400px wide)
  - Search toggle button with Lucide icon
  - Keyboard shortcuts (Enter, Escape, Arrow keys)
  - Click-outside-to-close
  - Auto-position next to button

- **Suggestions System**
  - Real-time autocomplete (300ms debounce)
  - Keyboard navigation (↑↓ arrows)
  - Suggestion highlighting
  - 2-character minimum query

- **Search Results**
  - Hierarchical results (location → years → visits)
  - Collapsible year sections
  - Visit count per location
  - Date range display
  - Duration estimates

- **Visit Navigation**
  - Click visit to zoom and highlight
  - Time filter events
  - 4-hour window around visit
  - Special visit markers (green circles)

- **Visit Creation**
  - Create visit from search result
  - Pre-filled form with location data
  - Datetime picker for start/end
  - Duration calculation
  - Validation

- **Map Integration**
  - Position relative to button
  - Maintains position during map pan/zoom
  - Prevents map scroll interference
  - Visits layer refresh after creation

---

## Family Sharing

### Family Members Controller (`family_members_controller.js`)

Real-time family member location sharing.

#### Features

- **Family Member Markers**
  - Circular avatars with email initials
  - Green color scheme (#10B981)
  - White border and shadow
  - Distinct from other markers

- **Real-time Updates**
  - ActionCable integration (FamilyLocationsChannel)
  - Incremental position updates
  - Recent update animation (< 5 minutes)
  - Pulse effect for active updates

- **Location Information**
  - Email address
  - Coordinates (6 decimal precision)
  - Battery level with colored icons
  - Battery status (charging/full)
  - Last seen timestamp

- **Battery Indicators**
  - Lucide battery icons
  - Color-coded: red (≤20%), orange (≤50%), green (>50%)
  - Charging icon when plugged in
  - Full battery indicator

- **Map Integration**
  - Permanent tooltips (last seen + battery)
  - Detailed popups on click
  - Theme-aware styling
  - Auto-zoom to fit all members
  - Layer control integration

- **Refresh Management**
  - 60-second periodic refresh (fallback)
  - Manual refresh button
  - Automatic stop when layer disabled
  - User feedback on manual refresh

---

## Controllers

### Base Controller (`base_controller.js`)

Common functionality for all Stimulus controllers.

### Other Controllers

- **`datetime_controller.js`**: Date/time picker initialization
- **`imports_controller.js`**: File import progress tracking
- **`trips_controller.js`**: Trip management UI
- **`stat_page_controller.js`**: Statistics page interactions
- **`clipboard_controller.js`**: Copy-to-clipboard functionality
- **`notifications_controller.js`**: Real-time notifications
- **`sharing_modal_controller.js`**: Public sharing UI
- **`map_preview_controller.js`**: Embedded map previews
- **`visit_modal_map_controller.js`**: Visit creation map
- **`add_visit_controller.js`**: Visit addition flow
- **`public_stat_map_controller.js`**: Public stat sharing maps

---

## Technical Details

### Map Controls & UI

- **Top-Right Buttons** (`maps/map_controls.js`)
  - Select Area tool
  - Add Visit button
  - Calendar toggle
  - Visits drawer toggle
  - Consistent ordering and styling

- **Theme Support** (`maps/theme_utils.js`)
  - Dark/light theme detection
  - Automatic control styling
  - Button theme adaptation
  - Panel theme colors
  - Oklahoma-based color system

### Helper Functions (`maps/helpers.js`)

- **Date Formatting**: Timezone-aware timestamp conversion
- **Distance Formatting**: km/miles with proper units
- **Speed Formatting**: km/h or mph conversion
- **Duration Formatting**: Days, hours, minutes display
- **Haversine Distance**: Accurate geographic distance calculation
- **Flash Messages**: User notification system

### Markers (`maps/markers.js`, `maps/marker_factory.js`)

- **Standard Markers**: CircleMarkers with popups
- **Live Markers**: Optimized for streaming
- **Popup Content**: Delete button, coordinates, timestamp, battery, velocity
- **Marker Clustering**: Performance optimization for large datasets

### Layers Configuration (`maps/layers.js`)

- **Raster Maps** (`raster_maps_config.js`)
  - OpenStreetMap
  - Stadia Maps (Alidade Smooth)
  - CartoDB
  - Stamen

- **Vector Maps** (`vector_maps_config.js`)
  - Self-hosted vector tiles
  - Optional fallback system

### Performance Monitoring

- **Tile Monitor** (`maps/tile_monitor.js`)
  - Track tile load times
  - Identify slow tiles
  - Performance metrics API

---

## WebSocket Channels

### PointsChannel (`channels/points_channel.js`)

Real-time GPS point streaming for live mode.

### TracksChannel

Real-time track updates (create/update/delete).

### FamilyLocationsChannel (`channels/family_locations_channel.js`)

Real-time family member location updates.

### NotificationsChannel (`channels/notifications_channel.js`)

System notifications and alerts.

### ImportsChannel (`channels/imports_channel.js`)

Import progress updates.

---

## Key Technologies

- **Leaflet.js**: Core mapping library
- **Stimulus**: JavaScript framework
- **Hotwired Turbo**: SPA-like navigation
- **ActionCable**: WebSocket integration
- **Canvas API**: High-performance rendering
- **GeoJSON**: Geographic data format
- **PostGIS**: Spatial database queries

---

## Configuration

Map features are controlled through user settings:

- `route_opacity`: Route visibility (0.0-1.0)
- `fog_of_war_meters`: Fog clear radius
- `fog_of_war_threshold`: Seconds between fog lines
- `meters_between_routes`: Route split distance
- `minutes_between_routes`: Route split time
- `time_threshold_minutes`: Visit detection threshold
- `merge_threshold_minutes`: Visit merge threshold
- `points_rendering_mode`: Raw or simplified
- `live_map_enabled`: Enable live mode
- `speed_colored_routes`: Enable speed colors
- `speed_color_scale`: Custom gradient definition
- `preferred_map_layer`: Base layer selection
- `enabled_map_layers`: Active overlay layers
- `maps.distance_unit`: km or mi
- `maps.url`: Custom tile server
- `immich_url`: Immich server
- `photoprism_url`: Photoprism server

---

## Data Flow

1. **Initial Load**: Server renders map with data attributes
2. **Controller Connect**: Stimulus initializes map and layers
3. **User Interaction**: Events trigger controller methods
4. **API Calls**: Fetch/update data via REST API
5. **WebSocket Updates**: Real-time data via ActionCable
6. **Layer Updates**: Incremental map updates
7. **Settings Persistence**: API saves user preferences

---

## Memory Management

- Bounded arrays for live mode (max 1000 points)
- Marker reference tracking for efficient updates
- Layer cleanup on disconnect
- Event listener removal
- Canvas context management
- GeoJSON data caching

---

## Accessibility Features

- Keyboard navigation for search
- Theme-aware color schemes
- Clear visual indicators
- Tooltip descriptions
- Confirmation dialogs for destructive actions
- Error message display
- Loading states

---

## Future Enhancements

Potential areas for expansion:

- Route editing capabilities
- Custom area shapes (polygons)
- Enhanced photo filtering
- Route comparison tools
- Advanced track statistics
- Export to GPX/GeoJSON
- Offline map support
- Route planning
- Custom marker icons
- Geofencing alerts
