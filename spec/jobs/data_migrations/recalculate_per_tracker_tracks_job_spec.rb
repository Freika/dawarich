# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculatePerTrackerTracksJob do
  # Retired with the points v2 rewrite, kept as a class because three shipped
  # migrations enqueue it by name. It must accept any legacy arguments and
  # touch nothing.
  it 'performs as a no-op without touching tracks or points' do
    create(:track, user: create(:user))

    expect { described_class.perform_now }.not_to(change { [Track.count, Point.count] })
  end

  it 'accepts the argument shapes the old migrations enqueue' do
    expect { described_class.perform_now(nil) }.not_to raise_error
  end
end
