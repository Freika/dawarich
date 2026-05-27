# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GeoJSON Point features without timestamps imported as Places' do
  subject(:run_import) { Geojson::Importer.new(import, user.id).call }

  let(:user) { create(:user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/geojson_timeless_points.json') }
  let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }
  let(:import) { create(:import, user:, name: 'points.json', source: 'geojson') }

  before do
    import.file.attach(io: File.open(file_path), filename: 'points.json', content_type: 'application/json')
  end

  it 'creates one Place per timeless Point feature with source :geojson_point' do
    expect { run_import }.to change { Place.where(user: user, source: :geojson_point).count }.by(2)
    expect(Place.where(user: user).pluck(:name)).to contain_exactly('point 1', 'point 2')
  end

  it 'creates no Points (timeless features do not belong on the timeline)' do
    expect { run_import }.not_to(change { Point.count })
  end

  it 'does not raise NoImportableDataError when all features land as Places' do
    expect { run_import }.not_to raise_error
  end
end
