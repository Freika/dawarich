# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillPlaceNameLocksJob, type: :job do
  describe '#perform' do
    it 'locks a renamed place without geodata' do
      place = create(:place, name: 'Grandma and Grandpa')

      described_class.perform_now

      expect(place.reload.name_locked_at).to be_present
    end

    it 'locks a renamed place whose name differs from its geodata-derived names' do
      place = create(:place, :with_geodata, name: 'Our favourite brewery')

      described_class.perform_now

      expect(place.reload.name_locked_at).to be_present
    end

    it 'does not lock places with the default name' do
      place = create(:place, name: Place::DEFAULT_NAME)

      described_class.perform_now

      expect(place.reload.name_locked_at).to be_nil
    end

    it 'does not lock geocoder-format machine names' do
      place = create(:place, :with_geodata, name: 'Braugasthaus Zum Alten Fritz (Restaurant)')

      described_class.perform_now

      expect(place.reload.name_locked_at).to be_nil
    end

    it 'does not lock builder-format machine names' do
      place = create(
        :place,
        :with_geodata,
        name: 'Braugasthaus Zum Alten Fritz, Greifswalder Chaussee, 84-85, Stralsund, Mecklenburg-Vorpommern'
      )

      described_class.perform_now

      expect(place.reload.name_locked_at).to be_nil
    end

    it 'leaves already-locked places untouched' do
      locked_at = 2.days.ago
      place = create(:place, name: 'Home', name_locked_at: locked_at)

      described_class.perform_now

      expect(place.reload.name_locked_at).to be_within(1.second).of(locked_at)
    end
  end
end
