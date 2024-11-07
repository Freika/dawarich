# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PointsChannel, type: :channel do
  let(:user) { create(:user) }

  before do
    stub_connection(current_user: user)
  end

  it 'subscribes to a stream for the current user' do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user)
  end
end
