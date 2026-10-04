# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Points web destroy follow-up' do
  let(:user) { create(:user, settings: { 'timezone' => 'Asia/Tokyo' }) }
  let(:timestamps) do
    [Time.utc(2025, 12, 31, 23, 30).to_i, Time.utc(2026, 1, 1, 0, 15).to_i, Time.utc(2026, 2, 1).to_i]
  end
  let(:payload) do
    { 'user_id' => user.id, 'timestamps' => timestamps, 'track_ids' => [91, 91, 92],
      'oldest_timestamp' => timestamps.min, 'timezone' => 'Europe/Berlin', 'locale' => 'de' }
  end

  def run = RailsCommands::Registry.handler('points.web_destroy_follow_up').call(payload)

  before do
    phoenix_tables!
    clear_achievement_checks(user.id)
    clear_enqueued_jobs
  end

  it 'follow-up covers exact months tracks epochs oldest achievement' do
    contexts = []
    allow(Points::TileEpoch).to receive(:bump) { contexts << [Time.zone.name, I18n.locale] }
    before = user.reload.attributes.slice('points_count', 'updated_at')
    run

    expect(Points::TileEpoch).to have_received(:bump).with(user.id, timestamps:)
    expect(enqueued_jobs.select { _1[:job] == Stats::CalculatingJob }.map { _1[:args] })
      .to eq([[user.id, 2026, 1], [user.id, 2026, 2]])
    expect(enqueued_jobs.select { _1[:job] == Tracks::RecalculateJob }.map { _1[:args] }).to eq([[91], [92]])
    expect(enqueued_jobs.select { _1[:job] == Achievements::CheckJob }.map { _1[:args] }).to eq([[user.id]])
    expect(Achievements::PendingChecks.read(user.id).first).to eq(timestamps.min)
    expect(contexts).to eq([['Europe/Berlin', :de]])
    expect(user.reload.attributes.slice('points_count', 'updated_at')).to eq(before)
  end

  it 'repeated delivery converges and achievement schedule debounces' do
    allow(Points::TileEpoch).to receive(:bump)
    expect { 2.times { run } }.to have_enqueued_job(Achievements::CheckJob).with(user.id).exactly(:once)
    expect(Points::TileEpoch).to have_received(:bump).twice
    expect(enqueued_jobs.count { _1[:job] == Stats::CalculatingJob }).to eq(4)
    expect(enqueued_jobs.count { _1[:job] == Tracks::RecalculateJob }).to eq(4)
    expect(Achievements::PendingChecks.read(user.id).first).to eq(timestamps.min)
  end

  it 'follow-up enqueue failure is retained by existing poller' do
    allow(Stats::CalculatingJob).to receive(:perform_later).and_raise(RuntimeError, 'synthetic stats enqueue failure')
    sql = ActiveRecord::Base.sanitize_sql_array([
                                                  'INSERT INTO phoenix.rails_commands(kind,payload) VALUES (?,?::jsonb)',
                                                  'points.web_destroy_follow_up', payload.to_json
                                                ])
    ActiveRecord::Base.connection.execute(sql)
    expect(RailsCommands::Poller.drain_once).to eq(1)
    query = 'SELECT attempts,leased_until,payload::text AS payload FROM phoenix.rails_commands'
    rows = ActiveRecord::Base.connection.select_all(query).to_a
    expect(rows.size).to eq(1)
    expect(rows.first).to include('attempts' => 1, 'leased_until' => nil)
    expect(JSON.parse(rows.first['payload'])).to eq(payload)
    expect(Stats::CalculatingJob).to have_received(:perform_later).with(user.id, 2026, 1)
    expect(enqueued_jobs).to be_empty
  end
end
