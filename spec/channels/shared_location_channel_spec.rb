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

    it 'keeps transmitting while the magic phrase is unchanged' do
      share.update!(magic_phrase: 'steady-phrase')
      stub_connection(current_user: nil, current_share: SharedLink.find(share.id))
      callback = nil
      allow_any_instance_of(described_class).to receive(:stream_for) do |_, _, **_options, &block|
        callback = block
      end

      subscribe(share_id: share.id)
      message = { 'latitude' => 1.0, 'longitude' => 2.0 }
      callback.call(message)

      expect(transmissions).to eq([message])
    end

    it 'stops transmitting once the owner regenerates the magic phrase' do
      share.update!(magic_phrase: 'old-phrase')
      stub_connection(current_user: nil, current_share: SharedLink.find(share.id))
      callback = nil
      allow_any_instance_of(described_class).to receive(:stream_for) do |_, _, **_options, &block|
        callback = block
      end

      subscribe(share_id: share.id)
      # The owner regenerates the phrase; the already-open connection still holds the old one.
      SharedLink.where(id: share.id).update_all(magic_phrase: 'new-phrase')
      callback.call('latitude' => 1.0, 'longitude' => 2.0)

      expect(transmissions).to be_empty
    end

    it 'still delivers the revoke notice so the viewer can show the link ended' do
      share.update!(magic_phrase: 'old-phrase')
      stub_connection(current_user: nil, current_share: SharedLink.find(share.id))
      callback = nil
      allow_any_instance_of(described_class).to receive(:stream_for) do |_, _, **_options, &block|
        callback = block
      end

      subscribe(share_id: share.id)
      # regenerate_phrase changes the phrase, then broadcasts the revoke notice.
      SharedLink.where(id: share.id).update_all(magic_phrase: 'new-phrase')
      callback.call('revoked' => true)

      expect(transmissions).to eq([{ 'revoked' => true }])
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
