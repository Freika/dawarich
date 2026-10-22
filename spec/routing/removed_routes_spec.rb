# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'removed routes', type: :routing do
  it 'does not route the settings maps page' do
    expect(get: '/settings/maps').not_to be_routable
  end

  it 'does not route settings maps updates' do
    expect(patch: '/settings/maps').not_to be_routable
  end
end
