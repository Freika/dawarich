# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Place name lock copy' do
  it 'names the sentinel the model actually matches, in every language' do
    I18n.available_locales.each do |locale|
      message = I18n.t('javascript.map_info.place_name_locked', locale: locale, fallback: false)

      expect(message).to include(Place::DEFAULT_NAME),
                         "#{locale} tells the reader to type a name that never unlocks the place"
    end
  end

  it 'hands the drawer the same sentinel rather than a translated one' do
    I18n.available_locales.each do |locale|
      message = I18n.t(
        'places.drawer.manual_name_title',
        default_name: Place::DEFAULT_NAME,
        locale: locale,
        fallback: false
      )

      expect(message).to include(Place::DEFAULT_NAME)
    end
  end

  it 'releases the lock when the place is renamed to that sentinel' do
    place = create(:place, name: 'Home', name_locked_at: Time.current)

    place.update!(name: Place::DEFAULT_NAME)

    expect(place.reload.name_locked_at).to be_nil
  end
end
