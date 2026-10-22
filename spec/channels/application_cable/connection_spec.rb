# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:owner) { create(:user) }

  context 'with an authenticated Warden user' do
    it 'connects (regression — existing path unchanged)' do
      connect env: { 'warden' => instance_double(Warden::Proxy, user: owner) }
      expect(connection.current_user).to eq(owner)
      expect(connection.current_share).to be_nil
    end
  end

  context 'with no warden user and no share id' do
    it 'is rejected' do
      expect { connect }.to have_rejected_connection
    end
  end

  context 'with an anonymous viewer of a phrase-free live share' do
    let(:share) { create(:shared_link, :live, user: owner) }

    it 'connects, identified by the share rather than a user' do
      connect params: { share_id: share.id }
      expect(connection.current_share).to eq(share)
      expect(connection.current_user).to be_nil
    end
  end

  context 'with an unknown share id' do
    it 'is rejected' do
      expect { connect params: { share_id: SecureRandom.uuid } }.to have_rejected_connection
    end
  end

  context 'with a revoked live share' do
    let(:share) { create(:shared_link, :live, :revoked, user: owner) }

    it 'is rejected' do
      expect { connect params: { share_id: share.id } }.to have_rejected_connection
    end
  end

  context 'with an expired live share' do
    let(:share) { create(:shared_link, :live, :expired, user: owner) }

    it 'is rejected' do
      expect { connect params: { share_id: share.id } }.to have_rejected_connection
    end
  end

  context 'with a non-live share id (e.g. a trip share)' do
    let(:trip) { create(:trip, user: owner) }
    let(:share) { create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id) }

    it 'is rejected — only live shares grant anonymous cable access' do
      expect { connect params: { share_id: share.id } }.to have_rejected_connection
    end
  end

  context 'with a phrase-protected live share' do
    let(:share) { create(:shared_link, :live, :with_phrase, user: owner) }

    it 'is rejected without the unlock cookie' do
      expect { connect params: { share_id: share.id } }.to have_rejected_connection
    end

    it 'connects with the matching encrypted unlock cookie' do
      cookies.encrypted["shared_link_#{share.id}"] = share.unlock_token
      connect params: { share_id: share.id }
      expect(connection.current_share).to eq(share)
      expect(connection.current_user).to be_nil
    end
  end

  context 'with an authenticated Warden user viewing a share' do
    let(:visitor) { create(:user) }
    let(:warden_env) { { 'warden' => instance_double(Warden::Proxy, user: visitor) } }

    it 'identifies a phrase-free live share alongside the user' do
      share = create(:shared_link, :live, user: owner)
      connect env: warden_env, params: { share_id: share.id }
      expect(connection.current_user).to eq(visitor)
      expect(connection.current_share).to eq(share)
    end

    it 'leaves the share unset for a revoked live share' do
      share = create(:shared_link, :live, :revoked, user: owner)
      connect env: warden_env, params: { share_id: share.id }
      expect(connection.current_user).to eq(visitor)
      expect(connection.current_share).to be_nil
    end

    it 'leaves the share unset for an expired live share' do
      share = create(:shared_link, :live, :expired, user: owner)
      connect env: warden_env, params: { share_id: share.id }
      expect(connection.current_share).to be_nil
    end

    it 'leaves the share unset for a non-live share' do
      trip = create(:trip, user: owner)
      share = create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id)
      connect env: warden_env, params: { share_id: share.id }
      expect(connection.current_share).to be_nil
    end

    it 'leaves the share unset for a phrase-protected share without the unlock cookie' do
      share = create(:shared_link, :live, :with_phrase, user: owner)
      connect env: warden_env, params: { share_id: share.id }
      expect(connection.current_share).to be_nil
    end

    it 'identifies a phrase-protected share with the matching encrypted unlock cookie' do
      share = create(:shared_link, :live, :with_phrase, user: owner)
      cookies.encrypted["shared_link_#{share.id}"] = share.unlock_token
      connect env: warden_env, params: { share_id: share.id }
      expect(connection.current_share).to eq(share)
    end
  end
end
