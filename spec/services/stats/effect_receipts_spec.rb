# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::EffectReceipts do
  it 'Rails digest generation holds the shared execution lock', :rxstats_shared_lock do
    receipt = SecureRandom.uuid
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    peer = PG.connect(host: config[:host], port: config[:port], dbname: config[:database],
                      user: config[:username], password: config[:password])
    result = nil

    described_class.once(receipt, 'digests.calculate_month') do
      result = peer.exec_params('SELECT pg_try_advisory_xact_lock(hashtextextended($1,0))', [receipt])[0].values.first
      :ok
    end

    expect(result).to eq('f')
  ensure
    peer&.close
  end
end
