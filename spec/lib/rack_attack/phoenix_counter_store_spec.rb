# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/rack_attack/phoenix_counter_store')

RSpec.describe RackAttack::PhoenixCounterStore do
  include ActiveSupport::Testing::TimeHelpers

  subject(:store) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }
  let(:key) { 'rack::attack:497484:shared_links/unlock:203.0.113.5:abc' }

  def expires_at
    connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(['SELECT expires_at FROM phoenix.counters WHERE key = ?', key])
    )
  end

  context 'when phoenix.counters exists' do
    before { phoenix_counters! }

    it 'adds to a live counter and starts an expired one again' do
      expect([store.increment(key, 1, expires_in: 60), store.increment(key, 1, expires_in: 60)]).to eq([1, 2])
      connection.execute("UPDATE phoenix.counters SET expires_at = statement_timestamp() - interval '1 second'")
      expect(store.increment(key, 1, expires_in: 60)).to eq(1)
    end

    it 'keeps the expiry the first increment of a window set' do
      store.increment(key, 1, expires_in: 60)
      first = expires_at
      store.increment(key, 1, expires_in: 3_600)
      expect(expires_at).to eq(first)
    end

    it 'is the store rack-attack counts with' do
      original = Rack::Attack.cache.store
      travel_to(Time.utc(2026, 10, 2, 12, 0, 0))
      Rack::Attack.enabled = true
      Rack::Attack.cache.store = store
      app = Rack::Attack.new(->(_env) { [200, {}, ['ok']] })
      env = -> { Rack::MockRequest.env_for('/s/abc/unlock', method: 'POST', 'REMOTE_ADDR' => '203.0.113.5') }
      expect(Array.new(6) { app.call(env.call).first }).to eq([200, 200, 200, 200, 200, 429])
      expect(connection.select_value(
               "SELECT value FROM phoenix.counters WHERE key LIKE 'rack::attack:%:shared_links/unlock:203.0.113.5:abc'"
             )).to eq(6)
    ensure
      travel_back
      Rack::Attack.cache.store = original
      Rack::Attack.enabled = false
    end
  end

  context 'when Phoenix has never migrated the database' do
    before do
      connection.execute('DROP TABLE phoenix.counters')
      PhoenixSchema.reset!
    end

    it 'warns once while the table is absent and resumes counting after migration' do
      expect(Rails.logger).to receive(:warn).with('event=rack_attack.store_unavailable reason=table_missing').once
      expect(store.increment(key, 1, expires_in: 60)).to be_nil
      expect(store.increment(key, 1, expires_in: 60)).to be_nil
      phoenix_counters!
      expect(store.increment(key, 1, expires_in: 60)).to eq(1)
      expect(store.increment(key, 1, expires_in: 60)).to eq(2)
    end

    it 'fails open without aborting the caller transaction' do
      ActiveRecord::Base.transaction do
        expect(store.increment(key, 1, expires_in: 60)).to be_nil
        expect { store.write(key, 1, expires_in: 60) }.not_to raise_error
        expect(connection.select_value('SELECT 1')).to eq(1)
      end
    end
  end
end
