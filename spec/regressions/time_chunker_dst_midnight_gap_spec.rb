# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TimeChunker iteration across a midnight DST start' do
  let(:user) { create(:user) }

  around do |example|
    Time.use_zone('America/Santiago') { example.run }
  end

  it 'spans a year that contains a midnight DST start without raising' do
    start_at = Time.zone.local(2026, 1, 1).beginning_of_day
    end_at   = Time.zone.local(2026, 12, 31).end_of_day

    chunker = Tracks::TimeChunker.new(user, start_at: start_at, end_at: end_at, chunk_size: 1.day)

    expect { chunker.call }.not_to raise_error
  end

  it 'returns chunks whose timestamps span the DST transition continuously' do
    create(:point, user: user, timestamp: Time.zone.local(2026, 9, 5, 12, 0, 0).to_i)
    create(:point, user: user, timestamp: Time.zone.local(2026, 9, 6, 12, 0, 0).to_i)

    start_at = Time.zone.local(2026, 9, 1).beginning_of_day
    end_at   = Time.zone.local(2026, 9, 30).end_of_day

    chunks = Tracks::TimeChunker.new(user, start_at: start_at, end_at: end_at, chunk_size: 1.day).call

    sept_5_ts = Time.zone.local(2026, 9, 5, 12, 0, 0).to_i
    sept_6_ts = Time.zone.local(2026, 9, 6, 12, 0, 0).to_i

    expect(chunks.any? { |c| c[:start_timestamp] <= sept_5_ts && c[:end_timestamp] >= sept_5_ts }).to be(true)
    expect(chunks.any? { |c| c[:start_timestamp] <= sept_6_ts && c[:end_timestamp] >= sept_6_ts }).to be(true)
  end
end
