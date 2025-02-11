# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Telemetry::Gather do
  let!(:user) { create(:user, last_sign_in_at: Time.zone.today) }

  describe '#call' do
    subject(:gather) { described_class.new.call }

    it 'returns a hash with measurement, timestamp, tags, and fields' do
      expect(gather).to include(:measurement, :timestamp, :tags, :fields)
    end

    it 'includes the correct measurement' do
      expect(gather[:measurement]).to eq('dawarich_usage_metrics')
    end

    it 'includes the current timestamp' do
      expect(gather[:timestamp]).to be_within(1).of(Time.current.to_i)
    end

    it 'includes the correct instance_id in tags' do
      expect(gather[:tags][:instance_id]).to eq(Digest::SHA2.hexdigest(user.api_key))
    end

    it 'includes the correct app_version in fields' do
      expect(gather[:fields][:app_version]).to eq("\"#{APP_VERSION}\"")
    end

    it 'includes the correct dau in fields' do
      expect(gather[:fields][:dau]).to eq(1)
    end

    context 'with a custom measurement' do
      let(:measurement) { 'custom_measurement' }

      subject(:gather) { described_class.new(measurement:).call }

      it 'includes the correct measurement' do
        expect(gather[:measurement]).to eq('custom_measurement')
      end
    end
  end
end
