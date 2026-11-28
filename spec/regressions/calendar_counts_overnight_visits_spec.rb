# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timeline::MonthSummary do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }

  let!(:visit) do
    create(:visit, user: user, status: :suggested, started_at: Time.utc(2026, 9, 30, 18, 0),
                   ended_at: Time.utc(2026, 10, 2, 6, 0), duration: 2160)
  end

  it 'counts an overnight visit and its share of the time on every day it covers' do
    days = described_class.new(user: user, month: '2026-10').call[:days]

    expect(days.slice('2026-10-01', '2026-10-02').transform_values do |day|
      day.slice(:visit_count, :suggested_count, :tracked_seconds)
    end).to eq(
      '2026-10-01' => { visit_count: 1, suggested_count: 1, tracked_seconds: 1440 * 60 },
      '2026-10-02' => { visit_count: 1, suggested_count: 1, tracked_seconds: 360 * 60 }
    )
  end

  it 'refreshes the cached next month after the visit is confirmed' do
    described_class.new(user: user, month: '2026-10').call

    visit.update!(status: :confirmed)

    expect(described_class.new(user: user, month: '2026-10').call[:status_counts]).to eq('confirmed' => 1)
  end

  it 'refreshes the cached next month after a bulk status change' do
    described_class.new(user: user, month: '2026-10').call

    Visits::BulkUpdate.new(user, [visit.id], 'confirmed').call

    expect(described_class.new(user: user, month: '2026-10').call[:status_counts]).to eq('confirmed' => 1)
  end

  it 'includes a visit that started in the previous month in the month status counts' do
    expect(described_class.new(user: user, month: '2026-10').call[:status_counts]).to eq('suggested' => 1)
  end
end
