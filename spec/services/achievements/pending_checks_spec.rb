# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::PendingChecks do
  let(:user_id) { 424_242 }
  let(:connection) { ActiveRecord::Base.connection }

  after { Sidekiq.redis { |r| r.del(Achievements::CheckJob.pending_key(user_id)) } }

  context 'with phoenix.achievement_checks' do
    before { phoenix_state! }

    it 'keeps the oldest deferral and consumes it only with the revision it read' do
      expect(described_class.read(user_id)).to eq([nil, nil])
      described_class.defer(user_id, 300)
      described_class.defer(user_id, 100)
      oldest, token = described_class.read(user_id)
      expect(oldest).to eq(100)

      described_class.defer(user_id, 250)
      described_class.consume(user_id, token)
      oldest, token = described_class.read(user_id)
      expect(oldest).to eq(100)

      described_class.consume(user_id, token)
      expect(described_class.read(user_id)).to eq([nil, nil])
      expect(Sidekiq.redis { |r| r.exists(Achievements::CheckJob.pending_key(user_id)) }).to eq(0)
    end

    it 'starts over from the new deferral once the pending value expired, and keeps it for three days' do
      described_class.defer(user_id, 100)
      connection.execute(
        'UPDATE phoenix.achievement_checks SET expires_at = statement_timestamp() - interval ' \
        "'1 second' WHERE user_id = #{user_id}"
      )
      expect(described_class.read(user_id)).to eq([nil, nil])

      described_class.defer(user_id, 900)
      expect(described_class.read(user_id).first).to eq(900)
      seconds = connection.select_value(
        'SELECT extract(epoch FROM expires_at - statement_timestamp()) FROM phoenix.achievement_checks ' \
        "WHERE user_id = #{user_id}"
      ).to_f
      expect(seconds).to be_between(3.days.to_i - 1, 3.days.to_i)
    end

    it 'issues the deferral statement Phoenix issues' do
      source = Rails.root.join('app-phoenix/lib/dawarich/points/anomaly_filter/effects.ex').read
      expect(described_class::DEFER.squish).to eq(source[/@defer """\n(.*?)\n\s*"""/m, 1].squish)
      expect(source).to include('@pending_ttl 259_200')
      expect(described_class::TTL).to eq(259_200)
    end
  end

  context 'without phoenix.achievement_checks' do
    before { without_phoenix_state! }

    it 'keeps the Redis set: the oldest member wins and a check removes only the members it read' do
      described_class.defer(user_id, 300)
      described_class.defer(user_id, 100)
      oldest, token = described_class.read(user_id)
      expect(oldest).to eq(100)

      described_class.defer(user_id, 200)
      described_class.consume(user_id, token)
      expect(described_class.read(user_id).first).to eq(200)
    end
  end
end
