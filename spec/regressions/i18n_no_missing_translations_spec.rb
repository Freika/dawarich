# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendered pages name every string they show', type: :request do
  let(:pages) do
    %i[
      map_path stats_path trips_path imports_path exports_path points_path places_path
      settings_general_index_path settings_integrations_path notifications_path
    ]
  end

  I18n.available_locales.each do |locale|
    it "renders every key page in #{locale} without a missing translation" do
      sign_in create(:user, settings: { 'locale' => locale.to_s })

      missing = pages.flat_map do |route|
        get send(route)
        response.body.scan(/translation missing: [^<",]*/).uniq.map { |key| "#{route}: #{key}" }
      end

      expect(missing).to be_empty
    end
  end
end
