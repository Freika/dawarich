# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::GenerationCommand do
  describe '.payload' do
    it 'payload round-trips through job_options with the bound zone' do
      start_at, end_at = Time.use_zone('America/New_York') do
        start_at = Time.zone.parse('2026-03-28 12:34:56.123456')
        end_at = Time.zone.parse('2026-03-29 08:07:06.654321')
        [start_at, end_at]
      end
      payload = described_class.payload(12, start_at:, end_at:, mode: :daily, untracked_only: false, import_id: 5,
                                        job_queue: :low_priority)

      expect(payload.values_at('start_at', 'end_at')).to all(match(/\.\d{6}[+-]\d{2}:\d{2}\z/))
      expect(payload['time_zone']).to eq('America/New_York')
      options = described_class.job_options(payload)
      expect(options).to include(
        mode: :daily,
        untracked_only: false,
        import_id: 5,
        job_queue: :low_priority
      )
      expect(options[:start_at].time_zone.name).to eq('America/New_York')
      expect(options[:end_at].time_zone.name).to eq('America/New_York')
      expect(options[:start_at]).to eq(start_at)
      expect(options[:end_at]).to eq(end_at)
    end

    it 'nil bounds keep the default zone' do
      payload = described_class.payload(12, start_at: nil, end_at: nil, mode: :bulk, untracked_only: true,
                                        import_id: nil, job_queue: nil)

      expect(payload).to include('time_zone' => Time.zone.tzinfo.name, 'start_at' => nil, 'end_at' => nil)
      expect(described_class.job_options(payload)).to include(start_at: nil, end_at: nil)
    end
  end
end
