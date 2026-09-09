# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  include Visits::AdvisoryLockable

  let(:user) { create(:user) }
  let(:base_ts) { 1_700_000_000 }

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: false, store_geodata?: false)
  end

  def seed_cluster(count = 6)
    Array.new(count) do |i|
      create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: base_ts + (i * 60), accuracy: 10, visit_id: nil)
    end
  end

  describe 'advisory lock' do
    it 'serializes the write phase with pg_advisory_xact_lock(user.id)' do
      skip 'advisory_locks disabled in test env' unless advisory_locks_enabled?

      seed_cluster

      sql_log = []
      original = ActiveRecord::Base.connection.method(:execute)
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql, *rest|
        sql_log << sql.to_s
        original.call(sql, *rest)
      end

      described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(sql_log.any? { |s| s.include?("pg_advisory_xact_lock(#{user.id})") }).to eq(true)
    end
  end

  describe 'happy path' do
    it 'creates visits when the pipeline finds stays' do
      seed_cluster

      visits = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(visits.size).to be >= 1
    end

    it 'fills the point→visit cache' do
      points = seed_cluster

      visits = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(visits.size).to be >= 1
      expect(points.map { |p| p.reload.visit_id }).to all(be_present)
    end
  end

  describe 'pipeline' do
    before { seed_cluster }

    it 'produces the expected scored visit for a known fixture (regression)' do
      visits = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(visits.size).to eq(1)
      visit = visits.first
      expect(visit.points.count).to eq(6)
      expect(visit.started_at.to_i).to eq(base_ts)
      expect(visit.ended_at.to_i).to eq(base_ts + 300)
      expect(visit.status).to eq('suggested')
      expect(visit.confidence).to be_present
      expect(visit.detection_version).to eq(Visits::Detection::VERSION)
    end

    it 'emits a structured Runner log' do
      pattern = /\[Visits::Detection::Runner\] user_id=#{user.id} range=\d+\.\.\d+ version=\d+ /
      pattern = /#{pattern}visits=\d+ duration_ms=\d+/
      expect(Rails.logger).to receive(:info).with(a_string_matching(pattern)).at_least(:once)
      allow(Rails.logger).to receive(:info)

      described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call
    end
  end

  describe 'failure handling' do
    it 'raises to the caller — there is no fallback detector' do
      seed_cluster(1)

      allow_any_instance_of(Visits::Detection::CandidateLoader).to receive(:call)
        .and_raise(ActiveRecord::StatementInvalid, 'statement timeout')

      expect { described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 1).call }
        .to raise_error(ActiveRecord::StatementInvalid, /statement timeout/)
    end
  end

  describe 'plan window clamping' do
    let(:lite_user) { create(:user, plan: :lite) }

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'clamps start_at to the data window for plan-restricted users' do
      window_start = lite_user.data_window_start.to_i
      requested_start = window_start - 30.days.to_i

      detector = described_class.new(lite_user, start_at: requested_start, end_at: window_start + 60)

      expect(detector.start_at).to eq(window_start)
    end

    it 'leaves start_at untouched for unrestricted (Pro) users' do
      pro_user = create(:user, plan: :pro)
      requested_start = base_ts - 365.days.to_i

      detector = described_class.new(pro_user, start_at: requested_start, end_at: base_ts)

      expect(detector.start_at).to eq(requested_start)
    end
  end
end
