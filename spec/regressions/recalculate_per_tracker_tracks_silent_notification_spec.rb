# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'DataMigrations::RecalculatePerTrackerTracksJob silences end-user notifications', type: :job do
  let(:user) { create(:user) }

  before do
    create(:track, user: user, tracker_id: nil)

    allow_any_instance_of(Users::RecalculateDataJob).to receive(:determine_years).and_return([Time.current.year])
    allow_any_instance_of(Users::RecalculateDataJob).to receive(:recalculate_stats)
    allow_any_instance_of(Users::RecalculateDataJob).to receive(:recalculate_tracks)
    allow_any_instance_of(Users::RecalculateDataJob).to receive(:recalculate_digests)
  end

  it 'does not create a "Data recalculation completed" notification' do
    expect do
      DataMigrations::RecalculatePerTrackerTracksJob.new.perform(user.id)
    end.not_to(change { user.notifications.where(title: 'Data recalculation completed').count })
  end

  it 'a direct Users::RecalculateDataJob call still creates a notification (default behavior preserved)' do
    expect do
      Users::RecalculateDataJob.new.perform(user.id)
    end.to change { user.notifications.where(title: 'Data recalculation completed').count }.by(1)
  end
end
