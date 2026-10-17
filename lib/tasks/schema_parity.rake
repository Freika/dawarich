# frozen_string_literal: true

namespace :schema_parity do
  desc 'Write db/release_migrations.json from the release tags'
  task release_map: :environment do
    path = Rails.root.join('db/release_migrations.json')
    states = SchemaParity::ReleaseMap.new(SchemaParity::GitTags.files_by_release).states
    if path.exist?
      missing = SchemaParity::ReleaseMap.missing_releases(JSON.parse(path.read).fetch('states'), states)
      if missing.any?
        abort "refusing to overwrite db/release_migrations.json: #{missing.size} release tags it lists are missing " \
              "locally (#{missing.first(5).join(', ')}); fetch the tags first"
      end
    end
    File.write(path, "#{JSON.pretty_generate(states: states)}\n")
    puts "#{states.size} states across #{states.sum { _1[:releases].size }} releases"
  end
end
