# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit suggestions recover from a transient deadlock' do
  let(:user) do
    create(:user, :pro_plan, settings: {
             'visits_suggestions_enabled' => 'true',
      'visit_radius_meters' => 100,
      'visit_min_points' => 3,
      'visit_min_duration_minutes' => 2,
      'timezone' => 'Etc/UTC'
           })
  end
  let(:first_day) { Time.utc(2026, 6, 15) }
  let(:arrivals) { [first_day + 12.hours, first_day + 1.day + 12.hours] }

  before { stub_const('Visits::SmartDetect::DEADLOCK_PAUSE_SECONDS', 0.0..0.0) }

  after do
    Sidekiq.redis { |redis| redis.del("visit_suggest_error:user:#{user.id}") }
    clear_enqueued_jobs
  end

  it 'retries the failed day instead of silently leaving its suggestion missing' do
    allow(Geocoder).to receive(:search).and_return([])
    arrivals.each_with_index do |arrival, day|
      [0, 120, 240].each do |offset|
        # Separate synthetic stays in the open South Pacific, so they cannot bridge.
        create(:point, user: user, lonlat: "POINT(#{-140.12345 + day} -40.12345)",
                       timestamp: arrival.to_i + offset, accuracy: 5, velocity: 0)
      end
    end

    deadlock_injected = false
    allow(Visit).to receive(:create!).and_wrap_original do |create_visit, **attributes|
      visit = create_visit.call(**attributes)
      unless deadlock_injected
        deadlock_injected = true
        # Fail inside Persister's transaction, as an invalidation trigger would.
        # The first insert and its revision writes must be rolled back.
        raise ActiveRecord::Deadlocked, 'synthetic deadlock in invalidate_achievement_collections()'
      end
      visit
    end

    expect do
      VisitSuggestingJob.perform_now(
        user_id: user.id, start_at: first_day, end_at: first_day + 2.days, release_debounce: false
      )
    end.not_to raise_error

    expect(deadlock_injected).to be(true)
    # The second day is also a positive control for the real detection pipeline.
    expect(user.visits.suggested.order(:started_at).pluck(:started_at)).to eq(arrivals)
    expect(user.points.where.not(visit_id: nil).count).to eq(6)
  end

  it 'gives up after three deadlocks and reports the failure the usual way' do
    allow(Geocoder).to receive(:search).and_return([])
    [0, 120, 240].each do |offset|
      create(:point, user: user, lonlat: 'POINT(-140.12345 -40.12345)',
                     timestamp: arrivals.first.to_i + offset, accuracy: 5, velocity: 0)
    end
    attempts = 0
    allow(Visit).to receive(:create!).and_wrap_original do |create_visit, **attributes|
      create_visit.call(**attributes)
      attempts += 1
      raise ActiveRecord::Deadlocked, 'synthetic deadlock in invalidate_achievement_collections()'
    end

    expect do
      VisitSuggestingJob.perform_now(
        user_id: user.id, start_at: first_day, end_at: first_day + 1.day, release_debounce: false
      )
    end.not_to raise_error

    expect(attempts).to eq(3)
    expect(user.visits.suggested).to be_empty
    expect(user.notifications.where(kind: :error).count).to eq(1)
  end

  it 'retries a full-history redetection month that deadlocks once' do
    allow(Geocoder).to receive(:search).and_return([])
    [0, 120, 240].each do |offset|
      create(:point, user: user, lonlat: 'POINT(-140.12345 -40.12345)',
                     timestamp: arrivals.first.to_i + offset, accuracy: 5, velocity: 0)
    end
    deadlock_injected = false
    allow(Visit).to receive(:create!).and_wrap_original do |create_visit, **attributes|
      visit = create_visit.call(**attributes)
      unless deadlock_injected
        deadlock_injected = true
        raise ActiveRecord::Deadlocked, 'synthetic deadlock in invalidate_achievement_collections()'
      end
      visit
    end

    result = Visits::Detection::HistoryRedetect.new(user).call

    expect(deadlock_injected).to be(true)
    expect(result.months_failed).to be_empty
    expect(user.visits.suggested.pluck(:started_at)).to eq([arrivals.first])
  end
end
