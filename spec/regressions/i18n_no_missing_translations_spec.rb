# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendered pages name every string they show', type: :request do
  let(:pages) do
    %i[
      map_path map_v2_path stats_path trips_path imports_path exports_path points_path places_path
      settings_general_index_path settings_integrations_path notifications_path
    ]
  end

  I18n.available_locales.each do |locale|
    it "renders every key page in #{locale} without a missing translation" do
      user = create(:user, settings: { 'locale' => locale.to_s })
      sign_in user

      missing = pages.flat_map do |route|
        get send(route)
        response.body.scan(/translation missing: [^<",]*/).uniq.map { |key| "#{route}: #{key}" }
      end

      get place_path(create(:place, user:))
      missing.concat(response.body.scan(/translation missing: [^<",]*/).uniq)
      translations = Nokogiri::HTML(response.body).at_css('#i18n-translations')
      expect(JSON.parse(translations.text).dig('places', 'move_pin')).to eq(
        I18n.t('javascript.places.move_pin', locale:, fallback: false)
      )
      expect(JSON.parse(translations.text).dig('map_info', 'geofence_boundary')).to eq(
        I18n.t('javascript.map_info.geofence_boundary', locale:, fallback: false, raise: true)
      )
      %w[
        places.inline_tags.new_tag places.inline_tags.name places.inline_tags.emoji places.inline_tags.create
        places.drawer.hidden_by_tag places.drawer.geofence_events places.drawer.no_geofence_events
        places.drawer.geofence_disabled
      ].each do |key|
        expect(I18n.t(key, locale:, fallback: false, raise: true, name: 'Home', radius: 500)).to be_present
      end
      expect(response.body).not_to include('translation_missing')
      expect(missing).to be_empty
    end
  end
end
