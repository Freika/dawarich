# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  let(:user) { create(:user) }
  let(:base_ts) { 1_700_000_000 }

  def advisory_locks_enabled?
    ActiveRecord::Base.connection_pool.db_config.configuration_hash[:advisory_locks] != false
  end

  describe 'advisory lock' do
    it 'acquires pg_advisory_xact_lock(user.id) when advisory locks are enabled' do
      skip 'advisory_locks disabled in test env' unless advisory_locks_enabled?

      create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: base_ts, accuracy: 10, visit_id: nil)

      sql_log = []
      original = ActiveRecord::Base.connection.method(:execute)
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql, *rest|
        sql_log << sql.to_s
        original.call(sql, *rest)
      end

      described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 1).call

      expect(sql_log.any? { |s| s.include?("pg_advisory_xact_lock(#{user.id})") }).to eq(true)
    end
  end

  describe 'happy path' do
    it 'creates visits when the detector finds clusters' do
      6.times do |i|
        create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                       timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
      end

      visits = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(visits.size).to be >= 1
    end

    it 'loads visit_id so confirmed-visit ownership checks do not raise MissingAttributeError' do
      points = Array.new(6) do |i|
        create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                       timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
      end

      visits = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(visits.size).to be >= 1
      expect(points.map { |p| p.reload.visit_id }).to all(be_present)
    end
  end

  describe 'detector' do
    before do
      6.times do |i|
        create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                       timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
      end
    end

    it 'uses StayPointDetector' do
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info).with(/detector=stay_point/).at_least(:once)

      visits = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(visits).not_to be_empty
    end

    it 'produces the expected scored visit for a known fixture (regression)' do
      visits = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(visits.size).to eq(1)
      visit = visits.first
      expect(visit.points.count).to eq(6)
      expect(visit.started_at.to_i).to eq(base_ts)
      expect(visit.ended_at.to_i).to eq(base_ts + 300)
      expect(visit.status).to eq('suggested')
      expect(visit.confidence).to be_present
    end

    it 'falls back to DbscanClusterer when StayPointDetector raises' do
      allow_any_instance_of(Visits::StayPointDetector).to receive(:call)
        .and_raise(ActiveRecord::StatementInvalid, 'statement timeout')
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:info)

      visits = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(visits).not_to be_empty
    end
  end

  describe 'failure handling' do
    it 're-raises when the fallback clusterer also fails' do
      create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: base_ts, accuracy: 10, visit_id: nil)

      allow_any_instance_of(Visits::StayPointDetector).to receive(:call)
        .and_raise(ActiveRecord::StatementInvalid, 'statement timeout')
      allow_any_instance_of(Visits::DbscanClusterer).to receive(:call)
        .and_raise(ActiveRecord::StatementInvalid, 'boom')
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)

      expect { described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 1).call }
        .to raise_error(ActiveRecord::StatementInvalid, /boom/)
    end
  end

  describe 'logging' do
    it 'emits a single structured INFO log' do
      3.times do |i|
        create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                       timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
      end

      log_pattern = /\[Visits::SmartDetect\] user_id=#{user.id} range=\d+\.\.\d+ detector=\w+ batches=\d+ /
      log_pattern_full = /#{log_pattern}points_in=\d+ clusters=\d+ visits_created=\d+ duration_ms=\d+/
      expect(Rails.logger).to receive(:info).with(a_string_matching(log_pattern_full)).at_least(:once)
      allow(Rails.logger).to receive(:info)

      described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call
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
