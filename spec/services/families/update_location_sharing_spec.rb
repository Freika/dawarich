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

    context 'when enabling with share_history and history_window' do
      let(:user) { create(:user) }
      let!(:family_membership) { create(:family_membership, user: user) }
      let(:enabled) { true }

      subject(:call_service) do
        described_class.new(
          user: user, enabled: enabled, duration: duration,
          share_history: share_history, history_window: history_window
        ).call
      end

      context 'with share_history true and history_window 7d' do
        let(:share_history) { 'true' }
        let(:history_window) { '7d' }

        it 'persists share_history as boolean true' do
          call_service
          user.reload
          expect(user.family_share_history?).to be true
        end

        it 'persists history_window as 7d' do
          call_service
          user.reload
          expect(user.family_history_window).to eq('7d')
        end
      end

      context 'with share_history false' do
        let(:share_history) { 'false' }
        let(:history_window) { '30d' }

        it 'persists share_history as boolean false' do
          call_service
          user.reload
          expect(user.family_share_history?).to be false
        end
      end

      context 'with invalid history_window' do
        let(:share_history) { nil }
        let(:history_window) { 'invalid_value' }

        it 'falls back to 24h' do
          call_service
          user.reload
          expect(user.family_history_window).to eq('24h')
        end
      end

      context 'with nil share_history preserves existing value' do
        let(:share_history) { nil }
        let(:history_window) { nil }

        before do
          user.update_family_location_sharing!(true, duration: 'permanent', share_history: true, history_window: '30d')
        end

        it 'preserves existing share_history' do
          call_service
          user.reload
          expect(user.family_share_history?).to be true
        end

        it 'preserves existing history_window' do
          call_service
          user.reload
          expect(user.family_history_window).to eq('30d')
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
