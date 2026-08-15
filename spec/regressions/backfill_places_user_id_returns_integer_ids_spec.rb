# frozen_string_literal: true

require 'rails_helper'

# Regression: job must be a no-op (not raise) when no userless places exist,
# which is always the case now that Place.user_id is NOT NULL at the DB level.
RSpec.describe DataMigrations::BackfillPlacesUserIdJob do
  let(:user) { create(:user) }

  it 'is a no-op and does not raise when all places already have a user_id' do
    create(:place, user: user)

    expect { described_class.perform_now }.not_to raise_error
  end
end
