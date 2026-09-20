# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedImport::Destroy do
  subject(:service) { described_class.new(import) }

  let(:user) { create(:user) }
  let(:import) do
    create(:import, user: user, source: :google_phone_takeout,
                    additional_data_extraction_status: :completed,
                    additional_data_extraction: { 'counts' => { 'visits' => 1 } })
  end

  describe '#call' do
    context 'with artifacts created by this extraction' do
      let!(:extracted_place) { create(:place, user: user, import_id: import.id) }
      let!(:extracted_visit) { create(:visit, user: user, place: extracted_place, import_id: import.id) }
      let!(:extracted_track) { create(:track, user: user, import_id: import.id) }
      let!(:extracted_segment) { create(:track_segment, track: extracted_track) }

      it 'removes the extracted visits, tracks and places' do
        expect { service.call }
          .to change(Visit, :count).by(-1)
          .and change(Track, :count).by(-1)
          .and change(Place, :count).by(-1)

        expect(Visit.exists?(extracted_visit.id)).to be false
        expect(Track.exists?(extracted_track.id)).to be false
        expect(Place.exists?(extracted_place.id)).to be false
      end

      it 'cascades track segments' do
        expect { service.call }.to change(TrackSegment, :count).by(-1)
        expect(TrackSegment.exists?(extracted_segment.id)).to be false
      end

      it 'resets the extraction state so the import can be re-extracted' do
        service.call
        import.reload

        expect(import.additional_data_extraction_not_attempted?).to be true
        expect(import.extraction_counts).to eq({})
      end
    end

    context 'when the extraction assigned points to a track' do
      let!(:extracted_track) { create(:track, user: user, import_id: import.id) }
      let!(:point) { create(:point, user: user, import_id: import.id, track_id: extracted_track.id) }

      it 'releases the points instead of deleting them' do
        expect { service.call }.not_to(change(Point, :count))
        expect(point.reload.track_id).to be_nil
      end
    end

    context 'when a place is still referenced by a visit Dawarich detected itself' do
      let!(:extracted_place) { create(:place, user: user, import_id: import.id) }
      let!(:extracted_visit) { create(:visit, user: user, place: extracted_place, import_id: import.id) }
      let!(:own_visit) { create(:visit, user: user, place: extracted_place, import_id: nil) }

      it 'keeps the place' do
        expect { service.call }.to change(Visit, :count).by(-1)

        expect(Place.exists?(extracted_place.id)).to be true
        expect(own_visit.reload.place_id).to eq(extracted_place.id)
      end
    end

    context 'with artifacts belonging to a different import' do
      let(:other_import) { create(:import, user: user, source: :google_phone_takeout) }
      let!(:other_visit) { create(:visit, user: user, import_id: other_import.id) }
      let!(:untouched_visit) { create(:visit, user: user, import_id: nil) }

      it 'leaves them alone' do
        expect { service.call }.not_to(change(Visit, :count))

        expect(Visit.exists?(other_visit.id)).to be true
        expect(Visit.exists?(untouched_visit.id)).to be true
      end
    end

    it 'is safe to run when nothing was extracted' do
      expect { service.call }.not_to raise_error
      expect(import.reload.additional_data_extraction_not_attempted?).to be true
    end
  end
end
