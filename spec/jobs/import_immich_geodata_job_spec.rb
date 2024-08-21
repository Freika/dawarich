# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportImmichGeodataJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    it 'calls Immich::ImportGeodata' do
      expect_any_instance_of(Immich::ImportGeodata).to receive(:call)

      ImportImmichGeodataJob.perform_now(user.id)
    end
  end
end
