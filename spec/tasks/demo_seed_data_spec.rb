# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'demo:seed_data' do
  it 'does not queue file processing for the GeoJSON imported directly by the task' do
    fixture = Rails.root.join('spec/fixtures/files/geojson/various_fields.geojson')
    task = Rake::Task['demo:seed_data']
    task.reenable

    allow_any_instance_of(Geojson::Importer).to receive(:call) { throw :after_import }

    expect do
      catch(:after_import) { task.invoke(fixture.to_s) }
    end.not_to have_enqueued_job(Import::ProcessJob)

    import = Import.where('name LIKE ?', 'Demo Data Import%').first!
    expect(import.file).not_to be_attached
  ensure
    task&.reenable
  end
end
