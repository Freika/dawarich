# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TripDetectionOrigin do
  let(:user) { create(:user) }

  def detected_trip(day, **attributes)
    started_at = Time.utc(2024, 1, 1) + (day * 10).days
    create(:trip, user:, origin: :detected, started_at:, ended_at: started_at + 3.days, **attributes)
  end

  describe '.replaceable_by_detection' do
    let!(:untouched) { detected_trip(0) }

    it 'holds untouched Detected Trips only' do
      create(:trip, user:) # manual
      detected_trip(1, user_edited_at: Time.current)
      annotated = detected_trip(2)
      create(:note, attachable: annotated, user:, noted_at: annotated.started_at + 1.hour)
      shared = detected_trip(3)
      create(:shared_link, user:, resource_type: :trip, resource_id: shared.id)

      expect(Trip.replaceable_by_detection).to contain_exactly(untouched)
    end
  end

  describe 'the user touching a Detected Trip' do
    it 'stays touched after its note is deleted' do
      trip = detected_trip(0)
      note = create(:note, attachable: trip, user:, noted_at: trip.started_at + 1.hour)

      expect(trip.reload.user_edited_at).to be_present

      note.destroy!
      expect(Trip.replaceable_by_detection).not_to include(trip)
    end

    it 'stays touched after its share link is deleted' do
      trip = detected_trip(0)
      link = create(:shared_link, user:, resource_type: :trip, resource_id: trip.id)

      expect(trip.reload.user_edited_at).to be_present

      link.destroy!
      expect(Trip.replaceable_by_detection).not_to include(trip)
    end

    it 'stays touched after a note attached later is detached again' do
      trip = detected_trip(0)
      note = create(:note, user:, noted_at: trip.started_at + 1.hour)
      previous_update = trip.updated_at

      note.update!(attachable: trip)
      expect(trip.reload).to have_attributes(user_edited_at: be_present, updated_at: be > previous_update)

      note.update!(attachable: nil)
      expect(Trip.replaceable_by_detection).not_to include(trip)
    end

    it 'never marks a manual trip' do
      trip = create(:trip, user:)
      create(:note, attachable: trip, user:, noted_at: trip.started_at + 1.hour)
      create(:shared_link, user:, resource_type: :trip, resource_id: trip.id)

      expect(trip.reload.user_edited_at).to be_nil
    end

    it 'keeps the first mark' do
      edited_at = Time.utc(2024, 12, 1, 10)
      trip = detected_trip(0, user_edited_at: edited_at)
      create(:shared_link, user:, resource_type: :trip, resource_id: trip.id)

      expect(trip.reload.user_edited_at).to eq(edited_at)
    end
  end

  describe '#destroy_by_user!' do
    it 'remembers the period of a Detected Trip' do
      trip = detected_trip(0)

      expect { trip.destroy_by_user! }.to change(user.trip_detection_dismissals, :count).by(1)
      expect(user.trip_detection_dismissals.last)
        .to have_attributes(started_at: trip.started_at, ended_at: trip.ended_at)
      expect(Trip.exists?(trip.id)).to be(false)
    end

    it 'remembers nothing for a manual trip' do
      trip = create(:trip, user:)

      expect { trip.destroy_by_user! }.not_to change(TripDetectionDismissal, :count)
      expect(Trip.exists?(trip.id)).to be(false)
    end
  end

  it 'refuses a second Detected Trip with the same period' do
    first = detected_trip(0)
    duplicate = build(:trip, user:, origin: :detected, started_at: first.started_at, ended_at: first.ended_at)

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
