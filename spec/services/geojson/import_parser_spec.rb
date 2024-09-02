# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geojson::ImportParser do
  describe '#call' do
    subject(:service) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }

    let(:user) { create(:user) }

    context 'when file content is an object' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/export.json') }
      let(:raw_data) { JSON.parse(File.read(file_path)) }
      let(:import) { create(:import, user:, name: 'geojson.json', raw_data:) }

      it 'creates new points' do
        expect { service }.to change { Point.count }.by(10)
      end
    end
  end
end
