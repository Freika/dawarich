# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:owner) { create(:user) }
  let(:visitor) { create(:user) }
  let(:share) { create(:shared_link, :live, user: owner) }

  it 'identifies the connection by the share even when a Warden user is present' do
    connect env: { 'warden' => instance_double(Warden::Proxy, user: visitor) },
            params: { share_id: share.id }

    expect(connection.current_share).to eq(share)
    expect(connection.current_user).to eq(visitor)
  end
end
