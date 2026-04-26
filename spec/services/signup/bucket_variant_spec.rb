# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signup::BucketVariant do
  before { Flipper.disable(:reverse_trial_signup) }

  describe 'self-hosted bypass' do
    it 'returns legacy_trial for self-hosted instances even when flag enabled' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      Flipper.enable(:reverse_trial_signup)

      user = build(:user, email: 'self-hosted@example.com')

      expect(described_class.new(user).call).to eq('legacy_trial')
    end

    it 'does not consult Flipper when self-hosted' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(Flipper).to receive(:enabled?).and_raise('Flipper should not be called')

      user = build(:user, email: 'self-hosted@example.com')

      expect(described_class.new(user).call).to eq('legacy_trial')
    end
  end

  describe 'cloud mode' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    context 'when the flag is disabled' do
      it 'returns legacy_trial for everyone' do
        user = build(:user, email: 'anyone@example.com')

        expect(described_class.new(user).call).to eq('legacy_trial')
      end
    end

    context 'when the flag is enabled globally' do
      before { Flipper.enable(:reverse_trial_signup) }

      it 'returns reverse_trial for everyone' do
        user = build(:user, email: 'anyone@example.com')

        expect(described_class.new(user).call).to eq('reverse_trial')
      end
    end

    context 'when the flag targets a specific persisted actor' do
      let(:target) { create(:user) }

      before { Flipper.enable_actor(:reverse_trial_signup, target) }

      it 'returns reverse_trial for that actor' do
        expect(described_class.new(target).call).to eq('reverse_trial')
      end

      it 'returns legacy_trial for a different actor' do
        other = create(:user)

        expect(described_class.new(other).call).to eq('legacy_trial')
      end
    end

    describe 'deterministic bucketing for unpersisted users' do
      it 'assigns the same variant to two users sharing an email' do
        Flipper.enable_percentage_of_actors(:reverse_trial_signup, 50)

        email = 'stable-bucket@example.com'
        result_a = described_class.new(build(:user, email: email)).call
        result_b = described_class.new(build(:user, email: email)).call

        expect(result_a).to eq(result_b)
      end

      it 'ignores case differences in the email' do
        Flipper.enable_percentage_of_actors(:reverse_trial_signup, 50)

        a = described_class.new(build(:user, email: 'MixedCase@Example.com')).call
        b = described_class.new(build(:user, email: 'mixedcase@example.com')).call

        expect(a).to eq(b)
      end

      it 'is deterministic across repeat calls on the same persisted user' do
        Flipper.enable_percentage_of_actors(:reverse_trial_signup, 50)
        user = create(:user)

        result_a = described_class.new(user).call
        result_b = described_class.new(user).call

        expect(result_a).to eq(result_b)
      end

      it 'distributes roughly 50/50 across many distinct emails when flag set to 50%' do
        Flipper.enable_percentage_of_actors(:reverse_trial_signup, 50)

        sample_size = 1000
        reverse_count = 0
        sample_size.times do |i|
          user = build(:user, email: "bucket-sample-#{i}-#{SecureRandom.hex(4)}@example.com")
          reverse_count += 1 if described_class.new(user).call == 'reverse_trial'
        end

        ratio = reverse_count.to_f / sample_size
        expect(ratio).to be_within(0.05).of(0.5)
      end
    end

    describe 'validation' do
      it 'raises ArgumentError on nil user' do
        expect { described_class.new(nil).call }.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError on blank email' do
        user = build(:user)
        user.email = ''

        expect { described_class.new(user).call }.to raise_error(ArgumentError, /email/)
      end

      it 'raises ArgumentError on nil email' do
        user = build(:user)
        user.email = nil

        expect { described_class.new(user).call }.to raise_error(ArgumentError, /email/)
      end
    end

    describe 'Flipper unavailability' do
      let(:user) { build(:user, email: 'flipper-down@example.com') }

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:reverse_trial_signup, anything)
          .and_raise(StandardError, 'flipper adapter offline')
      end

      it 'falls back to legacy_trial when Flipper raises' do
        expect(described_class.new(user).call).to eq('legacy_trial')
      end

      it 'logs a warning when Flipper raises' do
        expect(Rails.logger).to receive(:warn).with(/Flipper unavailable/)

        described_class.new(user).call
      end

      it 'does not propagate the exception' do
        expect { described_class.new(user).call }.not_to raise_error
      end
    end

    describe 'analytics telemetry' do
      it 'logs a structured signup_variant_assigned event with the variant' do
        Flipper.enable(:reverse_trial_signup)
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

      it 'logs the variant as legacy_trial when Flipper is off' do
        user = create(:user, email: 'telemetry-legacy@example.com')

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
        expect(json['variant']).to eq('legacy_trial')
      end
    end
  end
end
