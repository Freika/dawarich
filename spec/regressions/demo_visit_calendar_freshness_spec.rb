# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Demo visit calendar freshness' do
  self.use_transactional_tests = false

  let!(:user) { create(:user, settings: { 'timezone' => 'America/Los_Angeles' }) }
  let(:may) { Date.new(2026, 5, 1) }
  let(:june) { Date.new(2026, 6, 1) }

  after do
    user.visits.delete_all
    user.places.delete_all
    user.areas.delete_all
    user.notifications.delete_all
    user.delete
  end

  def summary(month)
    Timeline::MonthSummary.new(user: user, month: month).call[:status_counts]
  end

  def create_demo_visit
    create(:visit, user: user, area: nil, demo: true, status: :suggested,
                   started_at: Time.utc(2026, 6, 1, 6), ended_at: Time.utc(2026, 6, 1, 7))
  end

  it 'refreshes the status counts after a demo visit changes status' do
    visit = create_demo_visit
    expect(summary(may)).to eq('suggested' => 1)
    visit.update!(status: :confirmed)
    expect(summary(may)).to eq('confirmed' => 1)
  end

  it 'refreshes both local months when a demo visit moves across a month boundary' do
    visit = create_demo_visit
    expect(summary(may)).to eq('suggested' => 1)
    expect(summary(june)).to eq({})
    visit.update!(started_at: Time.utc(2026, 6, 1, 8), ended_at: Time.utc(2026, 6, 1, 9))
    expect(summary(may)).to eq({})
    expect(summary(june)).to eq('suggested' => 1)
  end

  it 'refreshes cached calendar counts after deleting a demo visit' do
    visit = create_demo_visit
    expect(summary(may)).to eq('suggested' => 1)
    visit.destroy!
    expect(summary(may)).to eq({})
  end

  it 'refreshes restored demo visit counts after null-island cleanup' do
    visit = create_demo_visit
    place = create(:place, user: user, lonlat: 'POINT(0 0)', latitude: 0, longitude: 0)
    visit.update!(place: place)
    expect(summary(may)).to eq('suggested' => 1)

    DataMigrations::CleanupNullIslandJob.perform_now(user.id)

    expect(Visit.exists?(visit.id)).to be false
    expect(summary(may)).to eq({})
  end

  it 'keeps cached counts valid when a demo visit edit is rolled back' do
    visit = create_demo_visit
    before = summary(may)
    Visit.transaction do
      visit.update!(status: :confirmed)
      raise ActiveRecord::Rollback
    end

    expect(summary(may)).to eq(before)
    expect(visit.reload).to be_suggested
  end
end
