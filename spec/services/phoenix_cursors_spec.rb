# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoenixCursors do
  let(:key) { 'spec:a12d1a:cursor' }

  after { Sidekiq.redis { |redis| redis.del(key) } }

  context 'with phoenix.cursors' do
    before { phoenix_tables! }

    it 'gets, sets, deletes and increments the row and leaves Redis alone' do
      expect(described_class.get(key)).to be_nil
      described_class.set(key, 41)
      expect(described_class.get(key)).to eq('41')
      expect(described_class.incr(key)).to eq(42)
      described_class.set(key, [7, -2_147_483_648].to_json)
      expect(described_class.get(key)).to eq('[7,-2147483648]')
      described_class.del(key)
      expect(described_class.get(key)).to be_nil
      expect(described_class.incr(key)).to eq(1)
      expect(Sidekiq.redis { |redis| redis.exists(key) }).to eq(0)
    end
  end

  it 'uses the Redis string on a database Phoenix never migrated' do
    ActiveRecord::Base.connection.execute('DROP TABLE phoenix.cursors')
    PhoenixSchema.reset!
    described_class.set(key, 5)
    expect(Sidekiq.redis { |redis| redis.get(key) }).to eq('5')
    expect(described_class.incr(key)).to eq(6)
    expect(described_class.get(key)).to eq('6')
    described_class.del(key)
    expect(Sidekiq.redis { |redis| redis.exists(key) }).to eq(0)
  end

  it 'issues the statements Dawarich.State issues' do
    source = Rails.root.join('app-phoenix/lib/dawarich/state.ex').read.squish
    %w[CURSOR PUT_CURSOR DELETE_CURSOR INCREMENT_CURSOR].each do |name|
      expect(source).to include(described_class.const_get(name).squish)
    end
  end
end
