# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signup::BucketVariant do
  describe '#call' do
    context 'when self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'returns legacy_trial' do
        user = build(:user, email: 'self-hosted@example.com')

        expect(described_class.new(user).call).to eq('legacy_trial')
      end
    end

    context 'when running as Cloud' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'returns reverse_trial for every user' do
        user = build(:user, email: 'anyone@example.com')

        expect(described_class.new(user).call).to eq('reverse_trial')
      end

      it 'returns reverse_trial regardless of which email signs up' do
        a = described_class.new(build(:user, email: 'a@example.com')).call
        b = described_class.new(build(:user, email: 'b@example.com')).call

        expect([a, b]).to eq(%w[reverse_trial reverse_trial])
      end

      describe 'analytics telemetry' do
        it 'logs a structured signup_variant_assigned event with the reverse_trial variant' do
          user = create(:user, email: 'telemetry@example.com')

          captured = []
          allow(Rails.logger).to receive(:info).and_wrap_original do |original, *args, &block|
            payload = block ? block.call : args.first
            if payload.is_a?(String) && payload.start_with?('{') && payload.include?('signup_variant_assigned')
              captured << payload
            end
            original.call(*args, &block)
          end

          described_class.new(user).call

          expect(captured).not_to be_empty
          json = JSON.parse(captured.first)
          expect(json['event']).to eq('signup_variant_assigned')
          expect(json['user_id']).to eq(user.id)
          expect(json['variant']).to eq('reverse_trial')
          expect(json['source']).to eq('bucket_variant')
        end
      end
    end
  end
end
