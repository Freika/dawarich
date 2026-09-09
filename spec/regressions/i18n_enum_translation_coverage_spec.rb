# frozen_string_literal: true

require 'rails_helper'

# Several views and Stimulus controllers build translation keys by interpolating
# an enum value, e.g. t("battery_statuses.#{point.battery_status}"). A value
# without a matching key renders the raw key or "translation missing" straight
# into the UI, so every reachable value needs an entry.
RSpec.describe 'I18n enum translation coverage' do
  {
    'battery_statuses' => -> { Point.battery_statuses.keys },
    'transportation_modes' => -> { Track::TRANSPORTATION_MODES.keys.map(&:to_s) },
    'visit_statuses' => -> { Visit.statuses.keys },
    'enums.import.source' => -> { Import.sources.keys },
    'enums.export.file_type' => -> { Export.file_types.keys },
    'enums.place.source' => -> { Place.sources.keys },
    'enums.shared_link.resource_type' => -> { SharedLink.resource_types.keys },
    'helpers.imports.extraction_status' => -> { Import.additional_data_extraction_statuses.keys }
  }.each do |scope, values|
    it "translates every #{scope} value" do
      missing = values.call.reject { |value| I18n.exists?("#{scope}.#{value}") }

      expect(missing).to be_empty, "missing #{scope} keys: #{missing.join(', ')}"
    end
  end

  it 'translates every status reachable through status_badge' do
    statuses = (Import.statuses.keys + Export.statuses.keys).uniq
    missing = statuses.reject { |status| I18n.exists?("statuses.#{status}") }

    expect(missing).to be_empty, "missing statuses keys: #{missing.join(', ')}"
  end
end
