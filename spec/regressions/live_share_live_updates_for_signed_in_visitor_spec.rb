# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Live share live updates for a signed-in visitor', type: :channel do
  let(:owner) { create(:user) }
  let(:visitor) { create(:user) }
  let(:share) { create(:shared_link, :live, user: owner) }

  describe ApplicationCable::Connection do
    it 'identifies the connection by the share even when a Warden user is present' do
      connect env: { 'warden' => instance_double(Warden::Proxy, user: visitor) },
              params: { share_id: share.id }

      expect(connection.current_share).to eq(share)
      expect(connection.current_user).to eq(visitor)
    end
  end

  describe SharedLocationChannel do
    it 'confirms the subscription for a signed-in visitor identified by the share' do
      stub_connection(current_user: visitor, current_share: share)

      subscribe(share_id: share.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for(share)
    end
  end
end
