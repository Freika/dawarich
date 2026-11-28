# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::VectorTileQuery do
  self.use_transactional_tests = false

  %i[call feature_rows].each do |operation|
    it "disables JIT only in the #{operation} transaction" do
      connection = Point.connection
      original = connection.select_value('SHOW jit')
      observed = []
      statements = []
      collector = lambda do |*args|
        sql = args.last[:sql]
        statements << sql
        observed << connection.select_value('SHOW jit') if sql.include?('WITH candidates AS')
      end

      connection.transaction do
        connection.execute('SET LOCAL jit = on')
        ActiveSupport::Notifications.subscribed(collector, 'sql.active_record') do
          described_class.new(scope: Point.none, z: 10, x: 512, y: 511).public_send(operation)
        end
        expect(observed).to eq(['off'])
        expect(statements.grep(/SET.*jit/i)).to eq(['SET LOCAL jit = off'])
        raise ActiveRecord::Rollback
      end
      expect(connection.select_value('SHOW jit')).to eq(original)
    end
  end
end
