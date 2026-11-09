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
