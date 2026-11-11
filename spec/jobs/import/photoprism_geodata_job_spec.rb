# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::PhotoprismGeodataJob, type: :job do
  let(:user) { create(:user, :with_photoprism_integration) }
  let(:photos) { stub_request(:get, 'https://photoprism.example.com/api/v1/photos').with(query: hash_including({})) }

  it 'retries when Photoprism times out' do
    photos.to_timeout

    expect { described_class.perform_now(user.id) }.to have_enqueued_job(described_class).with(user.id)
  end

  context 'when the saved URL answers with a redirect' do
    before { photos.to_return(status: 302, headers: { 'Location' => 'https://prism.example.com/api/v1/photos' }) }

    it 'tells the user which URL to save instead of ending silently' do
      expect { described_class.perform_now(user.id) }.to change { user.notifications.error.count }.by(1)

      expect(user.notifications.last.content).to include('https://prism.example.com', 'final URL')
    end

    it 'does not retry, because trying again cannot help' do
      expect { described_class.perform_now(user.id) }.not_to have_enqueued_job(described_class)
    end
  end
end
