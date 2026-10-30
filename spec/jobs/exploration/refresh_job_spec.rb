# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exploration::RefreshJob do
  let(:user) { create(:user) }

  before do
    allow(Exploration::Geography).to receive(:current).and_return(nil)
    Point.insert_all!([{ user_id: user.id, timestamp: 100, lonlat: 'POINT(13.35 52.51)',
                        created_at: Time.current, updated_at: Time.current }])
    clear_enqueued_jobs
  end

  it 'does not start a historical exploration rebuild from tracking alone' do
    expect(Exploration::State.find_by!(user_id: user.id).snapshot_id).to be_nil

    expect { described_class.perform_now }.not_to have_enqueued_job(Exploration::RebuildJob)
  end

  it 'recovers an explicit request after its queue claim expires' do
    Exploration::Schedule.call(user)
    Exploration::State.find_by!(user_id: user.id).update!(requested_at: 2.hours.ago)
    clear_enqueued_jobs

    expect { described_class.perform_now }.to have_enqueued_job(Exploration::RebuildJob).with(user.id)
  end

  it 'retries an explicit request after initial enqueue failure' do
    allow(Exploration::RebuildJob).to receive(:perform_later).and_raise('queue unavailable')
    Exploration::Schedule.call(user)
    allow(Exploration::RebuildJob).to receive(:perform_later).and_call_original
    clear_enqueued_jobs

    expect { described_class.perform_now }.to have_enqueued_job(Exploration::RebuildJob).with(user.id)
  end

  it 'moves later users to a new dataset when an earlier snapshot owner is soft-deleted' do
    old = Exploration::Dataset.create!(version: "old-#{SecureRandom.hex(4)}", completed_at: Time.current)
    current = Exploration::Dataset.create!(version: "new-#{SecureRandom.hex(4)}", completed_at: Time.current)
    allow(Exploration::Geography).to receive(:current).and_return(current)
    deleted = create(:user)
    [deleted, user].each do |owner|
      state = Exploration::State.find_or_create_by!(user_id: owner.id)
      snapshot = Exploration::Snapshot.create!(user_id: owner.id, dataset_id: old.id, revision: state.revision,
                                               world_opened_area: 1.0)
      state.update!(activated_at: Time.current, snapshot_id: snapshot.id, published_revision: state.revision)
    end
    deleted.update!(deleted_at: Time.current)
    clear_enqueued_jobs

    expect { described_class.perform_now }.to have_enqueued_job(Exploration::RebuildJob).with(user.id)
  end
end
