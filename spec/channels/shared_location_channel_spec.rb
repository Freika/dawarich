# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLocationChannel, type: :channel do
  let(:owner) { create(:user) }
  let(:share) { create(:shared_link, :live, user: owner) }

  context 'when the connection is authorized for this share' do
    before { stub_connection(current_user: nil, current_share: share) }

    it 'streams for the share' do
      subscribe(share_id: share.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for(share)
    end

    it 'rejects a subscription naming a different share id (cross-share escalation blocked)' do
      other = create(:shared_link, :live, user: owner)

      subscribe(share_id: other.id)

      expect(subscription).to be_rejected
    end
  end

  context 'when the connection has no authorized share' do
    before { stub_connection(current_user: nil, current_share: nil) }

    it 'rejects the subscription' do
      subscribe(share_id: share.id)

      expect(subscription).to be_rejected
    end
  end
end
