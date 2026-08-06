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

  describe 'confidence' do
    it 'is valid when nil' do
      expect(build(:visit, confidence: nil)).to be_valid
    end

    it 'is valid at the 0 and 100 bounds' do
      expect(build(:visit, confidence: 0)).to be_valid
      expect(build(:visit, confidence: 100)).to be_valid
    end

    it 'is invalid above 100' do
      expect(build(:visit, confidence: 120)).not_to be_valid
    end

    it 'is invalid below 0' do
      expect(build(:visit, confidence: -1)).not_to be_valid
    end

    describe '#confidence_band' do
      it 'returns nil when confidence is nil' do
        expect(build(:visit, confidence: nil).confidence_band).to be_nil
      end

      it 'returns :high for 70 and above' do
        expect(build(:visit, confidence: 70).confidence_band).to eq(:high)
        expect(build(:visit, confidence: 92).confidence_band).to eq(:high)
      end

      it 'returns :medium for 40..69' do
        expect(build(:visit, confidence: 40).confidence_band).to eq(:medium)
        expect(build(:visit, confidence: 69).confidence_band).to eq(:medium)
      end

      it 'returns :low for 0..39' do
        expect(build(:visit, confidence: 0).confidence_band).to eq(:low)
        expect(build(:visit, confidence: 39).confidence_band).to eq(:low)
      end
    end
  end

  describe 'soft deletion' do
    let(:user) { create(:user) }

    it 'excludes soft-deleted and declined visits from .active' do
      kept = create(:visit, user: user, status: :confirmed)
      tombstone = create(:visit, user: user, status: :confirmed, deleted_at: 1.day.ago)
      declined = create(:visit, user: user, status: :declined)

      expect(Visit.active).to include(kept)
      expect(Visit.active).not_to include(tombstone, declined)
    end

    it 'stamps deleted_at via #soft_delete!' do
      visit = create(:visit, user: user)

      expect { visit.soft_delete! }.to change { visit.reload.deleted_at }.from(nil)
      expect(Visit.count).to eq(1)
    end
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

    describe 'on decline' do
      it 'enqueues orphan-check because declined visits no longer keep a place alive' do
        expect { visit.update!(status: :declined) }
          .to have_enqueued_job(Places::DeleteIfOrphanJob).with(old_place.id)
      end
    end

    describe 'on soft delete' do
      it 'enqueues orphan-check when a visit is tombstoned' do
        expect { visit.soft_delete! }
          .to have_enqueued_job(Places::DeleteIfOrphanJob).with(old_place.id)
      end

      it 'deletes the place after the job runs when only the tombstone references it' do
        perform_enqueued_jobs { visit.soft_delete! }

        expect(Place.exists?(old_place.id)).to be false
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

    it 'does not bust the cache for demo visits (the demo importer busts once at the end)' do
      create(:visit, user: user, area: nil, place: nil, status: :confirmed,
                     started_at: in_month, ended_at: in_month + 1.hour, duration: 60)
      expect(summary_status_counts).to include('confirmed' => 1) # warm cache

      create(:visit, user: user, area: nil, place: nil, status: :suggested, demo: true,
                     started_at: in_month, ended_at: in_month + 1.hour, duration: 60)

      counts = summary_status_counts
      expect(counts).to include('confirmed' => 1)
      expect(counts).not_to include('suggested')
    end
  end
end
