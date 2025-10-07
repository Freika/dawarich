# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::UpdateLocationSharing do
  include ActiveSupport::Testing::TimeHelpers

  describe '.call' do
    subject(:call_service) do
      described_class.new(user: user, enabled: enabled, duration: duration).call
    end

    let(:duration) { '1h' }

    context 'when the user is in a family' do
      let(:user) { create(:user) }
      let!(:family_membership) { create(:family_membership, user: user) }

      context 'when enabling location sharing with a duration' do
        let(:enabled) { true }

        around do |example|
          travel_to(Time.zone.local(2024, 1, 1, 12, 0, 0)) { example.run }
        end

        it 'returns a successful result with the expected payload' do
          result = call_service

          expect(result).to be_success
          expect(result.status).to eq(:ok)
          expect(result.payload[:success]).to be true
          expect(result.payload[:enabled]).to be true
          expect(result.payload[:duration]).to eq('1h')
          expect(result.payload[:message]).to eq('Location sharing enabled for 1 hour')
          expect(result.payload[:expires_at]).to eq(1.hour.from_now.iso8601)
          expect(result.payload[:expires_at_formatted]).to eq(1.hour.from_now.strftime('%b %d at %I:%M %p'))
        end
      end

      context 'when disabling location sharing' do
        let(:enabled) { false }
        let(:duration) { nil }

        it 'returns a successful result without expiration details' do
          result = call_service

          expect(result).to be_success
          expect(result.payload[:success]).to be true
          expect(result.payload[:enabled]).to be false
          expect(result.payload[:message]).to eq('Location sharing disabled')
          expect(result.payload).not_to have_key(:expires_at)
          expect(result.payload).not_to have_key(:expires_at_formatted)
        end
      end

      context 'when update raises an unexpected error' do
        let(:enabled) { true }

        before do
          allow(user).to receive(:update_family_location_sharing!).and_raise(StandardError, 'boom')
        end

        it 'returns a failure result with internal server error status' do
          result = call_service

          expect(result).not_to be_success
          expect(result.status).to eq(:internal_server_error)
          expect(result.payload[:success]).to be false
          expect(result.payload[:message]).to eq('An error occurred while updating location sharing')
        end
      end
    end

    context 'when the user is not in a family' do
      let(:user) { create(:user) }
      let(:enabled) { true }

      it 'returns a failure result with unprocessable content status' do
        result = call_service

        expect(result).not_to be_success
        expect(result.status).to eq(:unprocessable_content)
        expect(result.payload[:success]).to be false
        expect(result.payload[:message]).to eq('Failed to update location sharing setting')
      end
    end
  end
end
