# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PointsLimitExceeded do
  describe '#call' do
    subject(:points_limit_exceeded) { described_class.new(user).call }

    let(:user) { create(:user) }

    context 'when app is self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      it { is_expected.to be false }
    end

    context 'when app is not self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        stub_const('DawarichSettings::BASIC_PAID_PLAN_LIMIT', 10)
      end

      context 'when user points count is equal to the limit' do
        before do
          allow(user).to receive(:points_count).and_return(10)
        end

        it { is_expected.to be true }

        it 'caches the result' do
          expect(user).to receive(:points_count).once
          2.times { described_class.new(user).call }
        end
      end

      context 'when user points count exceeds the limit' do
        before do
          allow(user).to receive(:points_count).and_return(11)
        end

        it { is_expected.to be true }
      end

      context 'when user points count is below the limit' do
        before do
          allow(user).to receive(:points_count).and_return(9)
        end

        it { is_expected.to be false }
      end
    end
  end
end
