# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visit, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:area).optional }
    it { is_expected.to belong_to(:place).optional }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:points).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:started_at) }
    it { is_expected.to validate_presence_of(:ended_at) }
    it { is_expected.to validate_presence_of(:duration) }
    it { is_expected.to validate_presence_of(:status) }

    it 'validates ended_at is greater than started_at' do
      visit = build(:visit, started_at: Time.zone.now, ended_at: Time.zone.now - 1.hour)

      expect(visit).not_to be_valid
      expect(visit.errors[:ended_at]).to include("must be greater than #{visit.started_at}")
    end
  end

  describe 'factory' do
    it { expect(build(:visit)).to be_valid }
  end

  describe 'self-cleanup callbacks' do
    include ActiveJob::TestHelper

    let(:user)      { create(:user) }
    let(:old_place) { create(:place, user: user, source: :photon) }
    let(:new_place) { create(:place, user: user, source: :photon) }
    let!(:visit)    { create(:visit, user: user, place: old_place, area: nil) }

    describe 'after_commit on: :update' do
      it 'enqueues orphan-check for the previous place when place_id changes' do
        expect { visit.update!(place: new_place) }
          .to have_enqueued_job(Places::DeleteIfOrphanJob).with(old_place.id)
      end

      it 'deletes the previous place after the job runs when it is orphan' do
        perform_enqueued_jobs { visit.update!(place: new_place) }

        expect(Place.exists?(old_place.id)).to be false
      end

      it 'does not enqueue when an unrelated attribute changes' do
        expect { visit.update!(name: 'Renamed') }
          .not_to have_enqueued_job(Places::DeleteIfOrphanJob)
      end

      it 'keeps the old place when it is still referenced by another visit' do
        create(:visit, user: user, place: old_place, area: nil)

        perform_enqueued_jobs { visit.update!(place: new_place) }

        expect(Place.exists?(old_place.id)).to be true
      end
    end

    describe 'after_destroy_commit' do
      it 'enqueues orphan-check for the destroyed visit place' do
        expect { visit.destroy! }
          .to have_enqueued_job(Places::DeleteIfOrphanJob).with(old_place.id)
      end

      it 'deletes the place after the job runs when it is orphan' do
        perform_enqueued_jobs { visit.destroy! }

        expect(Place.exists?(old_place.id)).to be false
      end

      it 'is a no-op when visit had no place' do
        orphan_visit = create(:visit, user: user, place: nil, area: nil)

        expect { orphan_visit.destroy! }.not_to raise_error
      end
    end
  end

  describe 'timeline month-summary cache invalidation' do
    let(:user)     { create(:user) }
    let(:month)    { Time.current.strftime('%Y-%m') }
    let(:in_month) { Time.current.beginning_of_month.change(hour: 10) }

    def summary_status_counts
      Timeline::MonthSummary.new(user: user, month: month).call[:status_counts]
    end

    it 'reflects a newly created visit instead of serving stale cached counts' do
      expect(summary_status_counts).to eq({}) # warms the 5-minute cache with zero visits

      create(:visit, user: user, area: nil, place: nil, status: :suggested,
                     started_at: in_month, ended_at: in_month + 1.hour, duration: 60)

      expect(summary_status_counts).to include('suggested' => 1)
    end

    it 'reflects a status change after the cache is warm' do
      visit = create(:visit, user: user, area: nil, place: nil, status: :suggested,
                             started_at: in_month, ended_at: in_month + 1.hour, duration: 60)
      expect(summary_status_counts).to include('suggested' => 1) # warm cache

      visit.update!(status: :confirmed)

      counts = summary_status_counts
      expect(counts).to include('confirmed' => 1)
      expect(counts).not_to include('suggested')
    end
  end
end
