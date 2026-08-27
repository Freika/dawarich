# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Google phone takeout numeric metadata ranges' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, name: 'phone_takeout.json') }

  it 'imports points when optional numeric metadata exceeds point column ranges' do
    document = {
      semanticSegments: [
        {
          startTime: '2024-06-15T09:00:00Z',
          altitudeMeters: -28_179_052_472_114_563,
          accuracyMeters: 36_759_892_106_056_213,
          visit: { topCandidate: { placeLocation: { latLng: '48.8566,2.3522' } } }
        }
      ]
    }

    import_document(document)

    point = user.points.find_by!(timestamp: Time.utc(2024, 6, 15, 9).to_i)
    expect(point.accuracy).to be_nil
    expect(point.altitude).to be_nil
  end

  it 'imports points when altitude exceeds the decimal column range' do
    document = {
      semanticSegments: [
        {
          startTime: '2024-06-15T10:00:00Z',
          altitudeMeters: 100_000_000,
          visit: { topCandidate: { placeLocation: { latLng: '48.8566,2.3522' } } }
        }
      ]
    }

    import_document(document)

    point = user.points.find_by!(timestamp: Time.utc(2024, 6, 15, 10).to_i)
    expect(point.altitude).to be_nil
  end

  it 'skips points whose timestamp exceeds the column range instead of failing the import' do
    document = {
      semanticSegments: [
        {
          startTime: '9999-12-31T23:59:59Z',
          visit: { topCandidate: { placeLocation: { latLng: '48.8566,2.3522' } } }
        },
        {
          startTime: '2024-06-15T11:00:00Z',
          visit: { topCandidate: { placeLocation: { latLng: '48.8566,2.3522' } } }
        }
      ]
    }

    import_document(document)

    expect(user.points.pluck(:timestamp)).to contain_exactly(Time.utc(2024, 6, 15, 11).to_i)
  end

  def import_document(document)
    Tempfile.create(['phone-takeout-numeric-ranges', '.json']) do |file|
      file.write(JSON.generate(document))
      file.flush

      expect do
        GoogleMaps::PhoneTakeoutImporter.new(import, user.id, file.path).call
      end.to change { Point.count }.by(1)
    end
  end
end
