# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::SemanticHistoryParser do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }
    let!(:import) { create(:import, user:) }
    let(:file_path) { Rails.root.join("spec/fixtures/files/google/location-history/#{file_name}.json") }

    before do
      import.file.attach(
        io: File.open(file_path),
        filename: 'semantic_history.json',
        content_type: 'application/json'
      )
    end

    context 'when activitySegment is present' do
      context 'when startLocation is blank' do
        let(:file_name) { 'with_activitySegment_without_startLocation' }

        it 'creates a point' do
          expect { parser }.to change(Point, :count).by(1)
          expect(Point.last.lonlat.to_s).to eq('POINT (12.3411111 12.3411111)')
        end

        context 'when waypointPath is blank' do
          let(:file_name) { 'with_activitySegment_without_startLocation_without_waypointPath' }

          it 'does not create a point' do
            expect { parser }.not_to change(Point, :count)
          end
        end
      end

      context 'when startLocation is present' do
        let(:file_name) { 'with_activitySegment_with_startLocation' }

        it 'creates a point' do
          expect { parser }.to change(Point, :count).by(1)
          expect(Point.last.lonlat.to_s).to eq('POINT (12.3422222 12.3422222)')
        end

        context 'with different timestamp formats' do
          context 'when timestamp is in ISO format' do
            let(:file_name) { 'with_activitySegment_with_startLocation_with_iso_timestamp' }

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
              expect(Point.last.lonlat.to_s).to eq('POINT (12.3433333 12.3433333)')
            end
          end

          context 'when timestamp is in seconds format' do
            let(:file_name) { 'with_activitySegment_with_startLocation_timestamp_in_seconds_format' }

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
              expect(Point.last.lonlat.to_s).to eq('POINT (12.3444444 12.3444444)')
            end
          end

          context 'when timestamp is in milliseconds format' do
            let(:file_name) { 'with_activitySegment_with_startLocation_timestamp_in_milliseconds_format' }

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
              expect(Point.last.lonlat.to_s).to eq('POINT (12.3455555 12.3455555)')
            end
          end

          context 'when timestampMs is used' do
            let(:file_name) { 'with_activitySegment_with_startLocation_timestampMs' }

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
              expect(Point.last.lonlat.to_s).to eq('POINT (12.3466666 12.3466666)')
            end
          end
        end
      end
    end

    context 'when placeVisit is present' do
      context 'when location with coordinates is present' do
        let(:file_name) { 'with_placeVisit_with_location_with_coordinates' }

        it 'creates a point' do
          expect { parser }.to change(Point, :count).by(1)
          expect(Point.last.lonlat.to_s).to eq('POINT (12.3477777 12.3477777)')
        end

        context 'with different timestamp formats' do
          context 'when timestamp is in ISO format' do
            let(:file_name) { 'with_placeVisit_with_location_with_coordinates_with_iso_timestamp' }

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
              expect(Point.last.lonlat.to_s).to eq('POINT (12.3488888 12.3488888)')
            end
          end

          context 'when timestamp is in seconds format' do
            let(:file_name) { 'with_placeVisit_with_location_with_coordinates_with_seconds_timestamp' }

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
              expect(Point.last.lonlat.to_s).to eq('POINT (12.3499999 12.3499999)')
            end
          end

          context 'when timestamp is in milliseconds format' do
            let(:file_name) { 'with_placeVisit_with_location_with_coordinates_with_milliseconds_timestamp' }

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
              expect(Point.last.lonlat.to_s).to eq('POINT (12.3511111 12.3511111)')
            end
          end

          context 'when timestampMs is used' do
            let(:file_name) { 'with_placeVisit_with_location_with_coordinates_with_timestampMs' }

            it 'creates a point' do
              expect { parser }.to change(Point, :count).by(1)
              expect(Point.last.lonlat.to_s).to eq('POINT (12.3522222 12.3522222)')
            end
          end
        end
      end

      context 'when location with coordinates is blank' do
        let(:file_name) { 'with_placeVisit_without_location_with_coordinates' }

        it 'does not create a point' do
          expect { parser }.not_to change(Point, :count)
        end

        context 'when otherCandidateLocations is present' do
          let(:file_name) { 'with_placeVisit_without_location_with_coordinates_with_otherCandidateLocations' }

          it 'creates a point' do
            expect { parser }.to change(Point, :count).by(1)
            expect(Point.last.lonlat.to_s).to eq('POINT (12.3533333 12.3533333)')
          end
        end
      end
    end
  end
end
