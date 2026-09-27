# frozen_string_literal: true

namespace :phoenix do
  desc 'Export the I18n backend for every available locale as JSON for Phoenix'
  task :i18n, [:path] => :environment do |_task, args|
    path = args[:path].presence || Rails.root.join('tmp/phoenix/i18n.json').to_s
    translations = I18n.backend.translations(do_init: true).slice(*I18n.available_locales)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(translations))
  end
end
