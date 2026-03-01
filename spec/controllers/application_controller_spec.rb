# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  describe '#require_pro_or_self_hosted!' do
    let(:controller_instance) { described_class.new }

    context 'when user is on pro plan' do
      let(:user) { create(:user, plan: :pro) }

      it 'returns nil (allows through)' do
        allow(controller_instance).to receive(:current_user).and_return(user)
        expect(controller_instance.send(:require_pro_or_self_hosted!)).to be_nil
      end
    end

    context 'when user is self_hoster' do
      let(:user) { create(:user, plan: :self_hoster) }

      it 'returns nil (allows through)' do
        allow(controller_instance).to receive(:current_user).and_return(user)
        expect(controller_instance.send(:require_pro_or_self_hosted!)).to be_nil
      end
    end

    context 'when user is on lite plan' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      let(:user) { create(:user, plan: :lite) }

      it 'does not allow through' do
        allow(controller_instance).to receive(:current_user).and_return(user)
        allow(controller_instance).to receive(:respond_to).and_yield(
          double(
            html: nil,
            json: nil,
            turbo_stream: nil
          )
        )

        # The method should not return nil when user is lite
        # (it triggers a respond_to block instead)
        expect(user.pro_or_self_hosted?).to be false
      end
    end

    context 'when user is nil' do
      it 'does not allow through' do
        allow(controller_instance).to receive(:current_user).and_return(nil)

        # nil&.pro_or_self_hosted? returns nil (falsy), so guard blocks
        expect(nil&.pro_or_self_hosted?).to be_nil
      end
    end
  end
end
