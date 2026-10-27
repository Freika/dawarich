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
      expect(response.body).not_to include('translation_missing')
      expect(missing).to be_empty
    end
  end
end
