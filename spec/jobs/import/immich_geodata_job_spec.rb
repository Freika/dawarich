# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::ImmichGeodataJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    it 'calls Immich::ImportGeodata' do
      expect_any_instance_of(Immich::ImportGeodata).to receive(:call)

      described_class.perform_now(user.id)
    end
  end
end

RSpec.describe Import::ImmichGeodataJob, 'connection failures', type: :job do
  let(:user) { create(:user, :with_immich_integration) }

  it 'retries when Immich times out' do
    stub_request(:post, 'https://immich.example.com/api/search/metadata').to_timeout

    expect { described_class.perform_now(user.id) }.to have_enqueued_job(described_class).with(user.id)
  end
end

RSpec.describe Import::ImmichGeodataJob, 'a refused redirect', type: :job do
  let(:user) { create(:user, :with_immich_integration) }

  before do
    stub_request(:post, 'https://immich.example.com/api/search/metadata')
      .to_return(status: 301, headers: { 'Location' => 'https://photos.example.com/api/search/metadata' })
  end

  it 'tells the user which URL to save instead of ending silently' do
    expect { described_class.perform_now(user.id) }.to change { user.notifications.error.count }.by(1)

    expect(user.notifications.last.content).to include('https://photos.example.com', 'final URL')
  end

  it 'does not retry, because trying again cannot help' do
    expect { described_class.perform_now(user.id) }.not_to have_enqueued_job(described_class)
  end
end
