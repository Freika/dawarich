# frozen_string_literal: true

namespace :phoenix do
  default = ->(args, key, name) { args[key].presence || Rails.root.join("tmp/phoenix/#{name}").to_s }

  desc 'Export the I18n backend for every available locale as JSON for Phoenix'
  task :i18n, [:path] => :environment do |_task, args|
    PhoenixBuildInputs.write(default.call(args, :path, 'i18n.json'), PhoenixBuildInputs.i18n_json)
  end

  desc 'Export the achievements registry with per-locale names as JSON for Phoenix'
  task :achievements, [:path] => :environment do |_task, args|
    PhoenixBuildInputs.write(default.call(args, :path, 'achievements.json'), PhoenixBuildInputs.achievements_json)
  end

  desc 'Export the importmap with its resolved asset paths as JSON for Phoenix (optionally through MANIFEST)'
  task :importmap, %i[path manifest] => :environment do |_task, args|
    PhoenixBuildInputs.write(default.call(args, :path, 'importmap.json'),
                             PhoenixBuildInputs.importmap_json(args[:manifest].presence))
  end

  desc 'Export the time zone choices of Settings > General as JSON for Phoenix'
  task :time_zones, [:path] => :environment do |_task, args|
    PhoenixBuildInputs.write(default.call(args, :path, 'time_zones.json'), PhoenixBuildInputs.time_zones_json)
  end

  desc 'Compile the precompile list with Sprockets into DIR and MANIFEST, leaving public/ alone'
  task :assets, %i[dir manifest] => :environment do |_task, args|
    PhoenixBuildInputs.compile_assets(args.fetch(:dir), args.fetch(:manifest))
  end

  desc 'Copy the gem-provided locale files and assets Phoenix builds from into the repository'
  task vendor: :environment do
    PhoenixBuildInputs.vendor!
  end
end
