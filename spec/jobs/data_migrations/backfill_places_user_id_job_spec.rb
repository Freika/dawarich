# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillPlacesUserIdJob, type: :job do
  let(:user_a) { create(:user) }

  describe '#perform' do
    it 'leaves places that already have user_id untouched' do
      place = create(:place, user: user_a)

      expect { described_class.perform_now }.not_to(change { place.reload.attributes })
    end

    it 'is a no-op when no userless places exist' do
      expect { described_class.perform_now }.not_to raise_error
    end
  end
end
