# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeslaMate::SyncJob, type: :job do
  it 'syncs the requested user' do
    user = create(:user)
    sync = instance_double(TeslaMate::Sync, call: { points: 0 })
    allow(TeslaMate::Sync).to receive(:new).with(user).and_return(sync)

    described_class.perform_now(user.id)

    expect(sync).to have_received(:call)
  end

  it 'no-ops for a missing user' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it 'notifies the user and re-raises when the sync is incomplete' do
    user = create(:user)
    sync = instance_double(TeslaMate::Sync)
    allow(sync).to receive(:call).and_raise(TeslaMate::Sync::IncompleteError, 'drive 42 failed')
    allow(TeslaMate::Sync).to receive(:new).with(user).and_return(sync)

    expect { described_class.perform_now(user.id) }.to raise_error(TeslaMate::Sync::IncompleteError)
    expect(user.notifications.last.content).to include('drive 42 failed')
  end
end
