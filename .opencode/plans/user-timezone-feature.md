# User Timezone Feature - Implementation Plan

## Overview

Allow users to select their own timezone from settings. The selected timezone will be stored in the database and used everywhere across the app for displaying dates and times. Points are stored as Unix epoch timestamps, so timezone conversion happens at display time.

## Current State

### What Exists
| Component | Location | Current Behavior |
|-----------|----------|------------------|
| `User#timezone` method | `app/models/user.rb:135-137` | Returns `Time.zone.name` (app-level timezone) |
| `settings` JSONB column | `db/schema.rb:496` | Stores user preferences, no timezone yet |
| `SafeSettings` class | `app/services/users/safe_settings.rb` | Typed accessors for settings, no timezone |
| `Stat#user_timezone` | `app/models/stat.rb:148-154` | Has commented code ready for user timezone |
| Map V2 | `app/views/map/maplibre/index.html.erb:10` | Passes `current_user.timezone` to JS |
| Map V1 | `app/views/map/leaflet/index.html.erb:20,26` | Also passes `current_user.timezone` |
| SQL Queries | `app/queries/stats/time_of_day_query.rb:32-34` | Support timezone parameter |
| Test expectation | `spec/services/users/export_import_integration_spec.rb:221,351` | Expects `settings['timezone']` |

### Issues to Fix
| File | Line(s) | Issue |
|------|---------|-------|
| `app/javascript/maps/tracks.js` | 21-22 | Hardcoded 'UTC' |
| `app/javascript/maps/visits.js` | 302-333, 880-896 | No timezone parameter |
| `app/javascript/maps_maplibre/components/visit_card.js` | 18-31 | No timezone |
| `app/javascript/maps_maplibre/layers/photos_layer.js` | 131 | No timezone |
| `app/javascript/maps_maplibre/components/photo_popup.js` | 23 | No timezone |
| `app/javascript/maps_maplibre/utils/search_manager.js` | 668-687 | No timezone |
| Various ERB views | Multiple | Direct `strftime` without timezone conversion |

---

## Configuration Decisions

| Decision | Choice |
|----------|--------|
| UI Location | New "General" settings tab |
| Default timezone | Auto-detect from browser, save silently |
| Scope | Everywhere (all views, APIs, maps) |
| Map V1 behavior | Will also respect user timezone |

---

## Implementation Plan

### Phase 1: Model & Settings Layer

**Goal:** Store and retrieve timezone from user settings

#### 1.1 Update `User#timezone` method
**File:** `app/models/user.rb`

```ruby
def timezone
  settings['timezone'].presence || Time.zone.name
end

def timezone=(value)
  self.settings = settings.merge('timezone' => value)
end
```

#### 1.2 Add timezone to SafeSettings
**File:** `app/services/users/safe_settings.rb`

- Add `'timezone' => nil` to `DEFAULT_VALUES`
- Add accessor method:
```ruby
def timezone
  @settings['timezone']
end
```

#### 1.3 Enable Stat#user_timezone
**File:** `app/models/stat.rb:148-154`

Uncomment the line that uses `user.timezone`:
```ruby
def user_timezone
  user.timezone.presence || Time.zone.name
end
```

---

### Phase 2: Settings UI - General Tab

**Goal:** Create new settings page for timezone selection

#### 2.1 Add route
**File:** `config/routes.rb`

```ruby
namespace :settings do
  resource :general, only: [:show, :update], controller: 'general'
  # ... existing routes
end
```

#### 2.2 Create controller
**File:** `app/controllers/settings/general_controller.rb` (NEW)

```ruby
# frozen_string_literal: true

module Settings
  class GeneralController < ApplicationController
    before_action :authenticate_user!

    def show
      @timezones = ActiveSupport::TimeZone.all.map { |tz| [tz.to_s, tz.name] }
    end

    def update
      if current_user.update(user_params)
        redirect_to settings_general_path, notice: 'Settings updated successfully.'
      else
        @timezones = ActiveSupport::TimeZone.all.map { |tz| [tz.to_s, tz.name] }
        render :show, status: :unprocessable_entity
      end
    end

    private

    def user_params
      settings = current_user.settings.merge(
        'timezone' => params.dig(:user, :timezone)
      )
      { settings: settings }
    end
  end
end
```

#### 2.3 Create view
**File:** `app/views/settings/general/show.html.erb` (NEW)

- Settings navigation partial
- Timezone dropdown with `ActiveSupport::TimeZone.all`
- Current timezone display with local time preview
- Save button

#### 2.4 Update navigation
**File:** `app/views/settings/_navigation.html.erb`

Add "General" tab as first item (before Integrations).

---

### Phase 3: Browser Timezone Auto-Detection

**Goal:** Automatically set timezone for users who haven't configured it

#### 3.1 Create Stimulus controller
**File:** `app/javascript/controllers/timezone_detection_controller.js` (NEW)

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    currentTimezone: String,
    updateUrl: String 
  }

  connect() {
    // Skip if user already has timezone set
    if (this.currentTimezoneValue) return

    const detectedTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (!detectedTimezone) return

    this.saveTimezone(detectedTimezone)
  }

  async saveTimezone(timezone) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    
    await fetch(this.updateUrlValue, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify({ user: { timezone: timezone } })
    })
  }
}
```

#### 3.2 Add API endpoint for timezone update
**File:** `app/controllers/api/v1/users_controller.rb` or `settings/general_controller.rb`

Add JSON-compatible update action.

#### 3.3 Include in application layout
**File:** `app/views/layouts/application.html.erb`

```erb
<% if user_signed_in? %>
  <div data-controller="timezone-detection"
       data-timezone-detection-current-timezone-value="<%= current_user.settings['timezone'] %>"
       data-timezone-detection-update-url-value="<%= settings_general_path(format: :json) %>">
  </div>
<% end %>
```

---

### Phase 4: Server-Side View Updates

**Goal:** All server-rendered dates respect user timezone

#### 4.1 Update ApplicationHelper date methods
**File:** `app/helpers/application_helper.rb`

Update `human_date`, `human_datetime`, `human_datetime_with_seconds` to accept optional user parameter:

```ruby
def human_datetime(datetime, user: current_user)
  return unless datetime

  datetime = datetime.in_time_zone(user&.timezone || Time.zone.name)
  datetime.strftime('%e %b %Y, %H:%M')
end
```

#### 4.2 Update views using direct strftime
Files to update:
- `app/views/visits/index.html.erb:79` - `visit.started_at.strftime`
- `app/views/visits/_visit.html.erb:5` - `started_at/ended_at.strftime`
- `app/views/visits/_modal.html.erb:9-11` - Multiple strftime calls
- `app/views/families/show.html.erb:14,88,184,188` - strftime calls
- `app/views/families/edit.html.erb:59,73` - strftime calls
- `app/views/family/invitations/show.html.erb:115` - strftime
- `app/views/family/invitations/index.html.erb:22,26` - strftime

Pattern for updates:
```erb
# Before
visit.started_at.strftime('%A, %d %B %Y')

# After
visit.started_at.in_time_zone(current_user.timezone).strftime('%A, %d %B %Y')
```

---

### Phase 5: JavaScript Updates

**Goal:** All JS date formatting uses user timezone

#### 5.1 Fix Map V1 tracks.js
**File:** `app/javascript/maps/tracks.js:21-22`

Change hardcoded 'UTC' to use userSettings.timezone:
```javascript
// Before
formatDate(track.start_at, 'UTC')

// After  
formatDate(track.start_at, userSettings.timezone)
```

#### 5.2 Fix Map V1 visits.js
**File:** `app/javascript/maps/visits.js`

Pass timezone to all date formatting calls (lines 302-333, 880-896).

#### 5.3 Fix Map V2 components

**visit_card.js** (`app/javascript/maps_maplibre/components/visit_card.js:18-31`)
- Accept timezone parameter in `create()` method
- Pass to `toLocaleString()` calls

**photo_popup.js** (`app/javascript/maps_maplibre/components/photo_popup.js:23`)
- Accept timezone parameter
- Pass to `toLocaleString()`

**photos_layer.js** (`app/javascript/maps_maplibre/layers/photos_layer.js:131`)
- Pass controller timezone to formatting

**search_manager.js** (`app/javascript/maps_maplibre/utils/search_manager.js:668-687`)
- Update `formatDateShort()` and `formatDateTime()` to accept timezone
- Pass timezone from controller

---

### Phase 6: Testing

#### 6.1 Unit Tests
**File:** `spec/models/user_spec.rb`

```ruby
describe '#timezone' do
  it 'returns settings timezone when set' do
    user.update!(settings: { 'timezone' => 'America/New_York' })
    expect(user.timezone).to eq('America/New_York')
  end

  it 'falls back to app timezone when not set' do
    expect(user.timezone).to eq(Time.zone.name)
  end
end
```

#### 6.2 Controller Tests
**File:** `spec/controllers/settings/general_controller_spec.rb` (NEW)

- Test show renders timezone dropdown
- Test update saves timezone to settings
- Test unauthorized access redirects

#### 6.3 System Tests
**File:** `spec/system/settings/general_spec.rb` (NEW)

- Test timezone selection and save
- Test timezone persists after page reload
- Test dates display in selected timezone

---

## Files Summary

### New Files (4)
| File | Purpose |
|------|---------|
| `app/controllers/settings/general_controller.rb` | General settings controller |
| `app/views/settings/general/show.html.erb` | Timezone settings UI |
| `app/javascript/controllers/timezone_detection_controller.js` | Auto-detect browser TZ |
| `spec/controllers/settings/general_controller_spec.rb` | Controller tests |

### Modified Files (15+)
| File | Changes |
|------|---------|
| `app/models/user.rb` | Update `timezone` method, add setter |
| `app/services/users/safe_settings.rb` | Add timezone accessor |
| `app/models/stat.rb` | Uncomment user_timezone code |
| `config/routes.rb` | Add settings/general routes |
| `app/views/settings/_navigation.html.erb` | Add General tab |
| `app/views/layouts/application.html.erb` | Add timezone detection controller |
| `app/helpers/application_helper.rb` | Update date helpers for timezone |
| `app/views/visits/index.html.erb` | Use timezone in strftime |
| `app/views/visits/_visit.html.erb` | Use timezone in strftime |
| `app/views/visits/_modal.html.erb` | Use timezone in strftime |
| `app/views/families/show.html.erb` | Use timezone in strftime |
| `app/javascript/maps/tracks.js` | Fix hardcoded UTC |
| `app/javascript/maps/visits.js` | Add timezone to formatting |
| `app/javascript/maps_maplibre/components/visit_card.js` | Add timezone param |
| `app/javascript/maps_maplibre/components/photo_popup.js` | Add timezone param |
| `app/javascript/maps_maplibre/layers/photos_layer.js` | Add timezone param |
| `app/javascript/maps_maplibre/utils/search_manager.js` | Add timezone to functions |

---

## Risks & Considerations

1. **Existing data consistency**: All timestamps are stored as Unix epoch (UTC), so conversion is only at display time. No data migration needed.

2. **Performance**: Timezone conversion in views is lightweight. No significant impact expected.

3. **Browser detection reliability**: `Intl.DateTimeFormat().resolvedOptions().timeZone` is supported in all modern browsers. Fallback to app timezone for older browsers.

4. **Test suite**: Some tests may assume app timezone. May need updates to use `Time.use_zone()` blocks.

5. **Cache invalidation**: User timezone changes may need to invalidate cached views/fragments that include timestamps.

---

## Estimated Effort

| Phase | Effort |
|-------|--------|
| Phase 1: Model Layer | 30 min |
| Phase 2: Settings UI | 1 hour |
| Phase 3: Auto-Detection | 45 min |
| Phase 4: Server Views | 1.5 hours |
| Phase 5: JavaScript | 1 hour |
| Phase 6: Testing | 1.5 hours |
| **Total** | **~6-7 hours** |
