# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookPolicy, type: :policy do
  let(:owner)   { create(:user, plan: :pro) }
  let(:webhook) { create(:webhook, user: owner) }

  context 'self-hosted' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    let(:policy) { described_class.new(owner, webhook) }

    it 'permits index' do
      expect(policy).to permit(:index)
    end

    it 'permits show' do
      expect(policy).to permit(:show)
    end

    it 'permits create' do
      expect(policy).to permit(:create)
    end

    it 'permits new' do
      expect(policy).to permit(:new)
    end

    it 'permits edit' do
      expect(policy).to permit(:edit)
    end

    it 'permits update' do
      expect(policy).to permit(:update)
    end

    it 'permits destroy' do
      expect(policy).to permit(:destroy)
    end

    it 'permits test' do
      expect(policy).to permit(:test)
    end
  end

  context 'cloud Pro owner' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    let(:policy) { described_class.new(owner, webhook) }

    it 'permits index' do
      expect(policy).to permit(:index)
    end

    it 'permits show' do
      expect(policy).to permit(:show)
    end

    it 'permits create' do
      expect(policy).to permit(:create)
    end

    it 'permits new' do
      expect(policy).to permit(:new)
    end

    it 'permits edit' do
      expect(policy).to permit(:edit)
    end

    it 'permits update' do
      expect(policy).to permit(:update)
    end

    it 'permits destroy' do
      expect(policy).to permit(:destroy)
    end

    it 'permits test' do
      expect(policy).to permit(:test)
    end
  end

  context 'cloud Lite owner' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    let(:lite_user) { create(:user, plan: :lite) }
    let(:lite_webhook) { create(:webhook, user: lite_user) }
    let(:policy) { described_class.new(lite_user, lite_webhook) }

    it 'permits index' do
      expect(policy).to permit(:index)
    end

    it 'forbids show' do
      expect(policy).not_to permit(:show)
    end

    it 'forbids create' do
      expect(policy).not_to permit(:create)
    end

    it 'forbids new' do
      expect(policy).not_to permit(:new)
    end

    it 'forbids edit' do
      expect(policy).not_to permit(:edit)
    end

    it 'forbids update' do
      expect(policy).not_to permit(:update)
    end

    it 'forbids destroy' do
      expect(policy).not_to permit(:destroy)
    end

    it 'forbids test' do
      expect(policy).not_to permit(:test)
    end
  end

  context 'different Pro user' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    let(:other_user) { create(:user, plan: :pro) }
    let(:policy)     { described_class.new(other_user, webhook) }

    it 'permits index' do
      expect(policy).to permit(:index)
    end

    it 'forbids show' do
      expect(policy).not_to permit(:show)
    end

    it 'forbids edit' do
      expect(policy).not_to permit(:edit)
    end

    it 'forbids update' do
      expect(policy).not_to permit(:update)
    end

    it 'forbids destroy' do
      expect(policy).not_to permit(:destroy)
    end

    it 'forbids test' do
      expect(policy).not_to permit(:test)
    end
  end
end
