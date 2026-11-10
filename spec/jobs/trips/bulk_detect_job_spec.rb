# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::BulkDetectJob do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user, status: :active) }

  def give_home(owner, **dates)
    create(:home, user: owner, place: create(:place, user: owner), **dates)
  end

  before do
    give_home(user, ended_on: Date.new(2020, 1, 1))
    give_home(user, started_on: Date.new(2021, 1, 1))
  end

  it 'is queued on the trips queue' do
    expect(described_class.new.queue_name).to eq('trips')
  end

  it 'enqueues one job per user with a Home' do
    create(:user)
    expect { described_class.perform_now }.to have_enqueued_job(Trips::DetectJob).with(user.id).exactly(:once)
  end

  it 'enqueues nothing for a user without a Home' do
    other = create(:user)
    expect { described_class.perform_now }.not_to have_enqueued_job(Trips::DetectJob).with(other.id)
  end

  it 'enqueues nothing for an inactive user with a Home' do
    inactive = create(:user, :inactive, skip_auto_trial: true)
    give_home(inactive)
    expect { described_class.perform_now }.not_to have_enqueued_job(Trips::DetectJob).with(inactive.id)
  end

  it 'includes a user on trial' do
    trial = create(:user, :trial, skip_auto_trial: true)
    give_home(trial)
    expect { described_class.perform_now }.to have_enqueued_job(Trips::DetectJob).with(trial.id)
  end

  it 'enqueues nothing when an operator switched trip detection off for the instance' do
    Flipper.add(:trip_detection)
    expect { described_class.perform_now }.not_to have_enqueued_job(Trips::DetectJob)
  end

  it 'still enqueues when the operator enabled trip detection only for some users' do
    Flipper.enable_actor(:trip_detection, user)
    expect { described_class.perform_now }.to have_enqueued_job(Trips::DetectJob).with(user.id)
  end

  it 'staggers the users in batches' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    later = create(:user, status: :active)
    give_home(later)

    freeze_time do
      expect { described_class.perform_now }
        .to have_enqueued_job(Trips::DetectJob).with(user.id).at(Time.current)
        .and have_enqueued_job(Trips::DetectJob).with(later.id).at(Time.current + described_class::STAGGER)
    end
  end
end
