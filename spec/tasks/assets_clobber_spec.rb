# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'assets:remove_manifest' do
  let(:manifest_path) { Rails.application.config.assets.manifest.to_s }

  after do
    FileUtils.rm_f(manifest_path)
  end

  it 'removes the sprockets manifest file' do
    FileUtils.mkdir_p(File.dirname(manifest_path))
    File.write(manifest_path, '{}')

    Rake::Task['assets:remove_manifest'].reenable
    Rake::Task['assets:remove_manifest'].invoke

    expect(File).not_to exist(manifest_path)
  end

  it 'runs as part of assets:clobber' do
    sources = Rake::Task['assets:clobber'].actions.filter_map(&:source_location).map(&:first)

    expect(sources).to include(Rails.root.join('lib/tasks/assets.rake').to_s)
  end
end
