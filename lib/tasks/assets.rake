# frozen_string_literal: true

namespace :assets do
  task remove_manifest: :environment do
    manifest = Rails.application.config.assets.manifest

    FileUtils.rm_f(manifest) if manifest
  end
end

if Rake::Task.task_defined?('assets:clobber')
  Rake::Task['assets:clobber'].enhance do
    Rake::Task['assets:remove_manifest'].invoke
  end
end
