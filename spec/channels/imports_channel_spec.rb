# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportsChannel, type: :channel do
  let(:user) { create(:user) }

  before do
    stub_connection(current_user: user)
  end

  it 'subscribes to a stream for the current user' do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user)
  end

  it 'rejects an anonymous (share-only) connection' do
    stub_connection(current_user: nil)

    subscribe

    expect(subscription).to be_rejected
  end
end
