# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::VectorTileQuery do
  self.use_transactional_tests = false

  [described_class, Tracks::SpeedVectorTileQuery].each do |query_class|
    it "disables JIT only inside the #{query_class.name} tile transaction" do
      connection = Track.connection
      original = connection.select_value('SHOW jit')
      observed = []
      statements = []
      collector = lambda do |*args|
        sql = args.last[:sql]
        statements << sql
        observed << connection.select_value('SHOW jit') if sql.match?(/\A\s*WITH /)
      end
      options = { scope: Track.none, z: 10, x: 512, y: 511 }
      options[:points_scope] = Point.none if query_class == Tracks::SpeedVectorTileQuery

      connection.transaction do
        connection.execute('SET LOCAL jit = on')
        ActiveSupport::Notifications.subscribed(collector, 'sql.active_record') do
          query_class.new(**options).call
        end
        expect(observed).to eq(['off'])
        expect(statements.grep(/SET.*jit/i)).to eq(['SET LOCAL jit = off'])
        raise ActiveRecord::Rollback
      end
      expect(connection.select_value('SHOW jit')).to eq(original)
    end
  end
end
