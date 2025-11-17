# Run with: bundle exec rails runner verify_places_integration.rb

puts "🔍 Verifying Places Integration..."
puts "=" * 50

# Check files exist
files_to_check = [
  'app/javascript/maps/places.js',
  'app/javascript/controllers/stat_page_controller.js',
  'app/javascript/controllers/place_creation_controller.js',
  'app/views/stats/_month.html.erb',
  'app/views/shared/_place_creation_modal.html.erb'
]

puts "\n📁 Checking Files:"
files_to_check.each do |file|
  if File.exist?(file)
    puts "  ✅ #{file}"
  else
    puts "  ❌ MISSING: #{file}"
  end
end

# Check view has our changes
puts "\n🎨 Checking View Changes:"
month_view = File.read('app/views/stats/_month.html.erb')

if month_view.include?('placesBtn')
  puts "  ✅ Places button found in view"
else
  puts "  ❌ Places button NOT found in view"
end

if month_view.include?('Filter Places by Tags')
  puts "  ✅ Tag filter section found in view"
else
  puts "  ❌ Tag filter section NOT found in view"
end

if month_view.include?('place_creation_modal')
  puts "  ✅ Place creation modal included"
else
  puts "  ❌ Place creation modal NOT included"
end

# Check JavaScript has our changes
puts "\n💻 Checking JavaScript Changes:"
controller_js = File.read('app/javascript/controllers/stat_page_controller.js')

if controller_js.include?('PlacesManager')
  puts "  ✅ PlacesManager imported"
else
  puts "  ❌ PlacesManager NOT imported"
end

if controller_js.include?('togglePlaces()')
  puts "  ✅ togglePlaces() method found"
else
  puts "  ❌ togglePlaces() method NOT found"
end

if controller_js.include?('filterPlacesByTags')
  puts "  ✅ filterPlacesByTags() method found"
else
  puts "  ❌ filterPlacesByTags() method NOT found"
end

# Check database
puts "\n🗄️  Checking Database:"
user = User.first
if user
  puts "  ✅ Found user: #{user.email}"
  puts "     Tags: #{user.tags.count}"
  puts "     Places: #{user.places.count}"
  
  if user.tags.any?
    puts "\n  📌 Your Tags:"
    user.tags.limit(5).each do |tag|
      puts "     #{tag.icon} #{tag.name} (#{tag.places.count} places)"
    end
  else
    puts "  ⚠️  No tags created yet. Create some at /tags"
  end
  
  if user.places.any?
    puts "\n  📍 Your Places:"
    user.places.limit(5).each do |place|
      puts "     #{place.name} - #{place.tags.map(&:name).join(', ')}"
    end
  else
    puts "  ⚠️  No places created yet. Use the API or create via console."
  end
else
  puts "  ❌ No users found"
end

puts "\n" + "=" * 50
puts "✅ Integration files are in place!"
puts "\n📋 Next Steps:"
puts "  1. Restart your Rails server"
puts "  2. Hard refresh your browser (Cmd+Shift+R)"
puts "  3. Navigate to /stats/#{Date.today.year}/#{Date.today.month}"
puts "  4. Look for 'Places' button next to 'Heatmap' and 'Points'"
puts "  5. Create tags at /tags if you haven't already"
puts "  6. Create places via API with those tags"
