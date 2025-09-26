namespace :webmanifest do
  desc "Generate site.webmanifest in public directory with correct asset paths"
  task :generate => :environment do
    require 'erb'

    # Make sure assets are compiled first by loading the manifest
    Rails.application.assets_manifest.assets

    # Get the correct asset paths
    icon_192_path = ActionController::Base.helpers.asset_path('favicon/android-chrome-192x192.png')
    icon_512_path = ActionController::Base.helpers.asset_path('favicon/android-chrome-512x512.png')

    # Generate the manifest content
    manifest_content = {
      "name": "Dawarich",
      "short_name": "Dawarich",
      "icons": [
        {
          "src": icon_192_path,
          "sizes": "192x192",
          "type": "image/png"
        },
        {
          "src": icon_512_path,
          "sizes": "512x512",
          "type": "image/png"
        }
      ],
      "theme_color": "#ffffff",
      "background_color": "#ffffff",
      "display": "standalone"
    }.to_json

    # Write to public/site.webmanifest
    File.write(Rails.root.join('public/site.webmanifest'), manifest_content)
    puts "Generated public/site.webmanifest with correct asset paths"
  end
end

# Hook to automatically generate webmanifest after assets:precompile
Rake::Task['assets:precompile'].enhance do
  Rake::Task['webmanifest:generate'].invoke
end