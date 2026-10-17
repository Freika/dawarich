# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoenixClaims do
  let(:connection) { ActiveRecord::Base.connection }
  let(:prefix) { "spec:#{SecureRandom.hex(4)}" }

  def live?(key)
    connection.select_value(
      "SELECT expires_at > statement_timestamp() FROM phoenix.once_claims WHERE key = #{connection.quote(key)}"
    )
  end

  def redis_keys = Sidekiq.redis { |r| r.keys("#{prefix}:*") }

  after do
    Sidekiq.redis do |r|
      keys = r.keys("#{prefix}:*")
      r.del(*keys) if keys.any?
    end
  end

  context 'with phoenix.once_claims (Phoenix migrated)' do
    before { phoenix_state! }

    it 'claims a key once until its claim expires, then again, and writes no Redis key' do
      key = "#{prefix}:a"
      expect(described_class.claim(key, 60)).to be(true)
      expect(described_class.claim(key, 60)).to be(false)
      expect(claim_seconds(key)).to be_between(59, 60)
      expire_claim_in(key, '-1 second')
      expect(described_class.claim(key, 60)).to be(true)
      expect(redis_keys).to be_empty
    end

    it 'claims many keys and returns exactly the ones it took' do
      live = "#{prefix}:live"
      old = "#{prefix}:old"
      fresh = "#{prefix}:new"
      described_class.claim(live, 60)
      described_class.claim(old, 60)
      expire_claim_in(old, '-1 second')

      expect(described_class.claim_all([fresh, live, old, fresh], 86_400)).to contain_exactly(fresh, old)
      expect(described_class.claim_all([], 60)).to eq([])
      expect(redis_keys).to be_empty
    end

    it 'unclaims one key or many' do
      keys = %w[a b c].map { "#{prefix}:#{_1}" }
      keys.each { described_class.claim(_1, 60) }

      described_class.unclaim(keys[0])
      described_class.unclaim_all([keys[1], "#{prefix}:none"])

      expect(keys.map { live?(_1) }).to eq([nil, nil, true])
    end

    it 'debounces: claims a free key, slides a live one, claims an expired or cleared one' do
      key = "#{prefix}:d"
      expect(described_class.debounce(key, 120)).to be(true)
      expire_claim_in(key, '10 seconds')
      expect(described_class.debounce(key, 120)).to be(false)
      expect(claim_seconds(key)).to be_between(119, 120)
      expire_claim_in(key, '-1 second')
      expect(described_class.debounce(key, 120)).to be(true)
      described_class.unclaim(key)
      expect(described_class.debounce(key, 120)).to be(true)
    end
  end

  context 'without phoenix.once_claims (Phoenix never migrated)' do
    before { without_phoenix_state! }

    it 'keeps the Redis semantics for claim, claim_all, debounce and unclaim' do
      a = "#{prefix}:a"
      b = "#{prefix}:b"
      expect(described_class.claim(a, 60)).to be(true)
      expect(described_class.claim(a, 60)).to be(false)
      expect(described_class.claim_all([a, b], 60)).to eq([b])
      expect(Sidekiq.redis { |r| r.ttl(b) }).to be_between(1, 60)
      described_class.unclaim_all([a, b])
      expect(redis_keys).to be_empty

      expect(described_class.debounce(a, 120)).to be(true)
      Sidekiq.redis { |r| r.expire(a, 10) }
      expect(described_class.debounce(a, 120)).to be(false)
      expect(Sidekiq.redis { |r| r.ttl(a) }).to be > 100
      described_class.unclaim(a)
      expect(redis_keys).to be_empty
    end
  end

  it 'issues the statements Dawarich.State issues' do
    source = Rails.root.join('app-phoenix/lib/dawarich/state.ex').read
    heredoc = ->(attribute) { source[/@#{attribute} """\n(.*?)\n\s*"""/m, 1].squish }
    line = ->(attribute) { source[/@#{attribute} "(.*?)"\n/, 1] }

    expect(described_class::CLAIM.squish).to eq(heredoc.call('claim'))
    expect(described_class::CLAIM_ALL.squish).to eq(heredoc.call('claim_all'))
    expect(described_class::SLIDE.squish).to eq(heredoc.call('slide'))
    expect(described_class::UNCLAIM).to eq(line.call('unclaim'))
    expect(described_class::UNCLAIM_ALL).to eq(line.call('unclaim_all'))
  end
end
