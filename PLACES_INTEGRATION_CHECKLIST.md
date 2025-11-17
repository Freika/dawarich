# Places Integration Checklist

## Files Modified:
- ✅ `app/javascript/controllers/stat_page_controller.js` - Added PlacesManager integration
- ✅ `app/javascript/maps/places.js` - Fixed API authentication headers
- ✅ `app/views/stats/_month.html.erb` - Added Places button and tag filters
- ✅ `app/views/shared/_place_creation_modal.html.erb` - Already exists

## What Should Appear:

### On Monthly Stats Page (`/stats/YYYY/MM`):

1. **Map Controls** (top right of map):
   - [ ] "Heatmap" button
   - [ ] "Points" button
   - [ ] **"Places" button** ← NEW!

2. **Below the Map**:
   - [ ] **"Filter Places by Tags"** section ← NEW!
   - [ ] Checkboxes for each tag you've created
   - [ ] Each checkbox shows: icon + name + color dot

## Troubleshooting Steps:

### Step 1: Restart Server
```bash
# Stop server (Ctrl+C)
bundle exec rails server

# Or with Docker:
docker-compose restart web
```

### Step 2: Hard Refresh Browser
- Mac: `Cmd + Shift + R`
- Windows/Linux: `Ctrl + Shift + R`

### Step 3: Check Browser Console
1. Open Developer Tools (F12)
2. Go to Console tab
3. Look for errors (red text)
4. You should see: "StatPage controller connected"

### Step 4: Verify URL
Make sure you're on a monthly stats page:
- ✅ `/stats/2024/11` ← Correct
- ❌ `/stats` ← Wrong (main stats index)
- ❌ `/stats/2024` ← Wrong (yearly stats)

### Step 5: Check JavaScript Loading
In browser console, type:
```javascript
console.log(document.querySelector('[data-controller="stat-page"]'))
```
Should show the element, not null.

### Step 6: Verify Controller Registration
In browser console:
```javascript
console.log(application.controllers)
```
Should include "stat-page" in the list.

## Expected Behavior:

### When You Click "Places" Button:
1. Places layer toggles on/off
2. Button highlights when active
3. Map shows custom markers with tag icons

### When You Check Tag Filters:
1. Map updates immediately
2. Shows only places with selected tags
3. Unchecking all shows all places

## If Nothing Shows:

### Check if you have any places created:
```bash
bundle exec rails console

# In console:
user = User.find_by(email: 'your@email.com')
user.places.count  # Should be > 0
user.tags.count    # Should be > 0
```

### Create test data:
```bash
bundle exec rails console

user = User.first
tag = user.tags.create!(name: "Test", icon: "📍", color: "#FF5733")

# Create via API or console:
place = user.places.create!(
  name: "Test Place",
  latitude: 40.7128,
  longitude: -74.0060,
  source: :manual
)
place.tags << tag
```

## Verification Script:

Run this in Rails console to verify everything:

```ruby
user = User.first
puts "Tags: #{user.tags.count}"
puts "Places: #{user.places.count}"
puts "Places with tags: #{user.places.joins(:tags).distinct.count}"

if user.tags.any?
  puts "\nYour tags:"
  user.tags.each do |tag|
    puts "  #{tag.icon} #{tag.name} (#{tag.places.count} places)"
  end
end

if user.places.any?
  puts "\nYour places:"
  user.places.limit(5).each do |place|
    puts "  #{place.name} at (#{place.latitude}, #{place.longitude})"
    puts "    Tags: #{place.tags.map(&:name).join(', ')}"
  end
end
```

## Still Having Issues?

Check these files exist and have the right content:
- `app/javascript/maps/places.js` - Should export PlacesManager class
- `app/javascript/controllers/stat_page_controller.js` - Should import PlacesManager
- `app/views/stats/_month.html.erb` - Should have Places button at line ~73

Look for JavaScript errors in browser console that might indicate:
- Import/export issues
- Syntax errors
- Missing dependencies
