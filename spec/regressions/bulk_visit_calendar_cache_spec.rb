# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Calendar cache after bulk visit status updates' do
  self.use_transactional_tests = false

  let(:user) { create_owner(settings: { 'timezone' => 'Europe/Berlin' }) }

  after do
    (@owners || []).each do |owner|
      owner.visits.delete_all
      owner.areas.delete_all
      owner.notifications.delete_all
      owner.delete
    end
  end

  def create_owner(**attributes)
    create(:user, **attributes).tap { |owner| (@owners ||= []) << owner }
  end

  def create_visit(user:, **attributes)
    create(:visit, user:, area: create(:area, user:), **attributes)
  end

  def summary(user, month)
    Timeline::MonthSummary.new(user:, month:).call
  end

  it 'refreshes cached suggested and confirmed counts after confirming visits' do
    visit = create_visit(user:, started_at: Time.utc(2026, 4, 22, 10), status: :suggested)
    expect(summary(user, '2026-04')[:status_counts]).to eq('suggested' => 1)

    Visits::BulkUpdate.new(user, [visit.id], 'confirmed').call

    expect(summary(user, '2026-04')[:status_counts]).to eq('confirmed' => 1)
    expect(summary(user, '2026-04')[:days]['2026-04-22'][:suggested_count]).to eq(0)
  end

  it 'removes declined visits from cached counts and calendar activity' do
    visit = create_visit(user:, started_at: Time.utc(2026, 4, 22, 10), status: :confirmed)
    expect(summary(user, '2026-04')[:days]['2026-04-22'][:visit_count]).to eq(1)

    Visits::BulkUpdate.new(user, [visit.id], 'declined').call

    expect(summary(user, '2026-04')[:status_counts]).to be_empty
    expect(summary(user, '2026-04')[:days]).not_to have_key('2026-04-22')
  end

  it 'invalidates each affected local month without evicting unrelated cached months or users' do
    april_visit = create_visit(user:, started_at: Time.utc(2026, 3, 31, 23), status: :suggested)
    may_visit = create_visit(user:, started_at: Time.utc(2026, 4, 30, 23), status: :suggested)
    foreign_visit = create_visit(user: create_owner, started_at: Time.utc(2026, 4, 10), status: :suggested)
    %w[2026-03 2026-04 2026-05].each { |month| summary(user, month) }
    summary(foreign_visit.user, '2026-04')
    untouched_key = Timeline::MonthSummary.cache_key_for(user, '2026-03')
    foreign_key = Timeline::MonthSummary.cache_key_for(foreign_visit.user, '2026-04')
    Rails.cache.write(untouched_key, :untouched)
    Rails.cache.write(foreign_key, :foreign)

    result = Visits::BulkUpdate.new(user, [april_visit.id, may_visit.id, foreign_visit.id], 'confirmed').call

    expect(result[:count]).to eq(2)
    %w[2026-04 2026-05].each do |month|
      expect(summary(user, month)[:status_counts]).to eq('confirmed' => 1)
    end
    expect(Rails.cache.read(untouched_key)).to eq(:untouched)
    expect(Rails.cache.read(foreign_key)).to eq(:foreign)
    expect(foreign_visit.reload.status).to eq('suggested')
  end

  it 'evicts the cached summary only after the surrounding transaction commits' do
    visit = create_visit(user:, started_at: Time.utc(2026, 4, 22), status: :suggested)
    cached = summary(user, '2026-04')
    key = Timeline::MonthSummary.cache_key_for(user, '2026-04')

    Visit.transaction do
      Visits::BulkUpdate.new(user, [visit.id], 'confirmed').call

      expect(Rails.cache.read(key)).to eq(cached)
    end

    expect(summary(user, '2026-04')[:status_counts]).to eq('confirmed' => 1)
  end

  it 'preserves the cached summary when the status change is rolled back' do
    visit = create_visit(user:, started_at: Time.utc(2026, 4, 22), status: :suggested)
    cached = summary(user, '2026-04')
    key = Timeline::MonthSummary.cache_key_for(user, '2026-04')

    Visit.transaction do
      Visits::BulkUpdate.new(user, [visit.id], 'confirmed').call
      raise ActiveRecord::Rollback
    end

    expect(Rails.cache.read(key)).to eq(cached)
    expect(visit.reload.status).to eq('suggested')
  end
end
