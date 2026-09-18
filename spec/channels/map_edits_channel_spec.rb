# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapEditsChannel, type: :channel do
  let(:user) { create(:user) }

  it 'subscribes an authenticated user to only their edit stream' do
    stub_connection current_user: user

    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user)
  end

  it 'rejects an anonymous connection' do
    stub_connection current_user: nil

    subscribe

    expect(subscription).to be_rejected
  end
end
