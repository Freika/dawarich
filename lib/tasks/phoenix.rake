# frozen_string_literal: true

namespace :phoenix do
  desc 'Export the I18n backend for every available locale as JSON for Phoenix'
  task :i18n, [:path] => :environment do |_task, args|
    path = args[:path].presence || Rails.root.join('tmp/phoenix/i18n.json').to_s
    translations = I18n.backend.translations(do_init: true).slice(*I18n.available_locales)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(translations))
  end

  desc 'Export the achievements registry with per-locale names as JSON for Phoenix'
  task :achievements, [:path] => :environment do |_task, args|
    path = args[:path].presence || Rails.root.join('tmp/phoenix/achievements.json').to_s
    definitions = Achievements::Registry.all.map do |definition|
      {
        'key' => definition.key, 'kind' => definition.kind, 'level' => definition.level.to_s,
        'flat' => definition.flat?, 'threshold' => definition.threshold, 'total' => definition.total,
        'target' => definition.target, 'regions' => definition.regions, 'region_codes' => definition.region_codes,
        'names' => I18n.available_locales.to_h do |locale|
          [locale.to_s, I18n.with_locale(locale) { Achievements::SetPresenter.new(definition:).name }]
        end
      }
    end
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate('definitions' => definitions))
  end

  desc 'Export the importmap with its resolved asset paths as JSON for Phoenix'
  task :importmap, [:path] => :environment do |_task, args|
    path = args[:path].presence || Rails.root.join('tmp/phoenix/importmap.json').to_s
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, Rails.application.importmap.to_json(resolver: ActionController::Base.helpers))
  end

  desc 'Export the time zone choices of Settings > General as JSON for Phoenix'
  task :time_zones, [:path] => :environment do |_task, args|
    path = args[:path].presence || Rails.root.join('tmp/phoenix/time_zones.json').to_s
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate('options' => Object.new.extend(UserHelper).settings_time_zone_options))
  end
end
