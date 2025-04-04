# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geojson::ImportParser do
  describe '#call' do
    subject(:service) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }

    let(:user) { create(:user) }

    context 'when file content is an object' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/export.json') }
      let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }
      let(:import) { create(:import, user:, name: 'geojson.json', file:) }

      before do
        import.file.attach(io: File.open(file_path), filename: 'geojson.json', content_type: 'application/json')
      end

      it 'creates new points' do
        expect { service }.to change { Point.count }.by(10)
      end
    end
  end
end
