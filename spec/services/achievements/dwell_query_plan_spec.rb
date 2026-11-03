# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'achievement dwell queries' do
  self.use_transactional_tests = false

  let(:user) { create(:user) }
  let(:connection) { ApplicationRecord.connection }

  after { user.destroy }

  def nestloop_during_cells_queries(&block)
    observed = []
    collector = lambda do |*args|
      observed << connection.select_value('SHOW enable_nestloop') if args.last[:sql].include?('WITH cells AS')
    end
    ActiveSupport::Notifications.subscribed(collector, 'sql.active_record', &block)
    observed
  end

  {
    'grid dwell' => ->(u) { Achievements::GridDwellCalculator.new(u, table: 'regions').call },
    'grid first seen' => ->(u) { Achievements::GridDwellCalculator.new(u, table: 'regions').first_seen },
    'country dwell' => ->(u) { Achievements::CountryDwellCalculator.new(u).call },
    'country first seen' => ->(u) { Achievements::CountryDwellCalculator.new(u).first_seen }
  }.each do |name, run|
    it "plans the #{name} query without nested loops and restores the session setting" do
      original = connection.select_value('SHOW enable_nestloop')

      observed = nestloop_during_cells_queries { run.call(user) }

      expect(observed).not_to be_empty
      expect(observed.uniq).to eq(['off'])
      expect(connection.select_value('SHOW enable_nestloop')).to eq(original)
    end
  end

  def cells_sql(&block)
    captured = []
    collector = ->(*args) { captured << args.last[:sql] if args.last[:sql].include?('WITH cells AS') }
    ActiveSupport::Notifications.subscribed(collector, 'sql.active_record', &block)
    captured.first
  end

  it 'looks up each grid cell polygon once, whatever plan the points join gets' do
    sql = cells_sql { Achievements::GridDwellCalculator.new(user, table: 'regions').call }

    plan = connection.select_values("EXPLAIN #{sql}").join("\n")

    expect(plan).to include('CTE cell_codes')
  end

  it 'caps the query with a statement timeout' do
    observed = []
    collector = lambda do |*args|
      observed << connection.select_value('SHOW statement_timeout') if args.last[:sql].include?('WITH cells AS')
    end
    ActiveSupport::Notifications.subscribed(collector, 'sql.active_record') do
      Achievements::GridDwellCalculator.new(user, table: 'regions').call
    end

    expect(observed.uniq).to eq(['10min'])
  end

  describe 'a statement that runs past the timeout' do
    before { stub_const('Achievements::PlannedRows::STATEMENT_TIMEOUT', '50ms') }

    def expect_cancelled_and_settings_restored(&block)
      originals = %w[enable_nestloop statement_timeout].map { |name| connection.select_value("SHOW #{name}") }

      expect(&block).to raise_error(ActiveRecord::QueryCanceled)
      expect(%w[enable_nestloop statement_timeout].map { |name| connection.select_value("SHOW #{name}") })
        .to eq(originals)
      expect(connection.select_value('SELECT 1')).to eq(1)
    end

    it 'raises QueryCanceled and leaves the connection usable' do
      expect_cancelled_and_settings_restored { Achievements::PlannedRows.select('SELECT pg_sleep(1)') }
    end

    it 'raises QueryCanceled inside an outer transaction' do
      expect_cancelled_and_settings_restored do
        connection.transaction { Achievements::PlannedRows.select('SELECT pg_sleep(1)') }
      end
    end
  end
end
