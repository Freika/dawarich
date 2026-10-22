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
end
