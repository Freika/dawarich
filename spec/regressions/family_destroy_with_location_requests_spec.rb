# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family deletion with location-sharing requests' do
  it 'destroys the family and its location requests' do
    family = create(:family)
    create(:family_location_request, family: family)

    expect { family.destroy! }.to change(Family::LocationRequest, :count).by(-1)

    expect(Family.exists?(family.id)).to be(false)
  end
end
