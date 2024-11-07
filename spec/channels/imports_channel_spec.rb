# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportsChannel, type: :channel do
  let(:user) { create(:user) }
  let(:import) { create(:import) }

  before { stub_connection current_user: user }

  describe '#subscribe' do
    it 'confirms the subscription and subscribes to a stream' do
      subscribe(import_id: import.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for(import)
    end

    it 'rejects the subscription without import_id' do
      subscribe

      expect(subscription).to be_rejected
    end
  end

  describe '#broadcast' do
    it 'broadcasts a message to the stream' do
      subscribe(import_id: import.id)

      expect do
        ImportsChannel.broadcast_to(import, message: 'Test message')
      end.to have_broadcasted_to(import).with(message: 'Test message')
    end
  end
end
