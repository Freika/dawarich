# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Date and time preferences for JavaScript', type: :request do
  let(:user) do
    create(:user, settings: { 'date_format' => 'yyyy-mm-dd', 'time_format' => '12h', 'first_day_of_week' => 'sunday' })
  end

  def meta_preferences
    meta = Nokogiri::HTML(response.body).at_css('head meta[name="date-time-preferences"]')
    JSON.parse(meta['content'])
  end

  def javascript_translations
    JSON.parse(Nokogiri::HTML(response.body).at_css('#i18n-translations').text)
  end

  before { sign_in user }

  it 'exposes the preferences in the application layout' do
    get settings_general_index_path

    expect(meta_preferences)
      .to eq('date_format' => 'yyyy-mm-dd', 'time_format' => '12h', 'first_day_of_week' => 'sunday')
  end

  it 'exposes the preferences and the 12h clock strings in the map layout' do
    get map_path

    expect(meta_preferences['time_format']).to eq('12h')
    expect(javascript_translations['date_time_preferences'])
      .to eq('clock_12h' => I18n.t('date_time_preferences.clock_12h'), 'meridiem' => { 'am' => 'AM', 'pm' => 'PM' })
  end
end
