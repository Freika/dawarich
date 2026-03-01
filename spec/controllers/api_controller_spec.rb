# frozen_string_literal: true

require 'rails_helper'

# Test the plan-gating guard via a real API endpoint.
# We use the health endpoint (GET /api/v1/health) as the test vehicle
# and test the guard method directly on the controller instance.
RSpec.describe ApiController, type: :controller do
  describe '#require_pro_or_self_hosted_api!' do
    let(:controller_instance) { described_class.new }

    context 'when user is on pro plan' do
      let(:user) { create(:user, plan: :pro) }

      it 'returns nil (allows through)' do
        allow(controller_instance).to receive(:current_api_user).and_return(user)
        expect(controller_instance.send(:require_pro_or_self_hosted_api!)).to be_nil
      end
    end

    context 'when user is self_hoster' do
      let(:user) { create(:user, plan: :self_hoster) }

      it 'returns nil (allows through)' do
        allow(controller_instance).to receive(:current_api_user).and_return(user)
        expect(controller_instance.send(:require_pro_or_self_hosted_api!)).to be_nil
      end
    end

    context 'when user is on lite plan' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      let(:user) { create(:user, plan: :lite) }

      it 'renders 403 forbidden' do
        allow(controller_instance).to receive(:current_api_user).and_return(user)
        allow(controller_instance).to receive(:render)

        controller_instance.send(:require_pro_or_self_hosted_api!)

        expect(controller_instance).to have_received(:render).with(
          json: hash_including(error: 'pro_plan_required'),
          status: :forbidden
        )
      end
    end

    context 'when user is nil' do
      it 'renders 403 forbidden' do
        allow(controller_instance).to receive(:current_api_user).and_return(nil)
        allow(controller_instance).to receive(:render)

        controller_instance.send(:require_pro_or_self_hosted_api!)

        expect(controller_instance).to have_received(:render).with(
          json: hash_including(error: 'pro_plan_required'),
          status: :forbidden
        )
      end
    end
  end
end
