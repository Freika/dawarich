# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::BulkDetectJob do
  let(:user) { create(:user) }

  before do
    place = create(:place, user:)
    create(:home, user:, place:, ended_on: Date.new(2020, 1, 1))
    create(:home, user:, place:, started_on: Date.new(2021, 1, 1))
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
end
