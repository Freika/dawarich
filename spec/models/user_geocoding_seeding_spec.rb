# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, 'geocoding seeding' do
  # Geocoding is an Instance setting. Seeding a per-user copy on every signup
  # produced rows nothing reads, and after the resolver took over it would have
  # gated on resolved values while writing raw constants.
  it 'does not create per-user geocoding settings when a user is created' do
    user = create(:user)

    expect(user.service_settings.service_geocoding).to be_empty
  end

  it 'no longer registers the seeding callback' do
    expect(described_class._create_callbacks.map(&:filter)).not_to include(:seed_geocoding_settings_from_env)
  end
end
