# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculateFlightMonthsJob do
  it 'recalculates each user who has flights' do
    flyer = create(:user)
    create(:flight, user: flyer)
    create(:user)

    expect { described_class.perform_now }
      .to have_enqueued_job(DataMigrations::RecalculateUserFlightMonthsJob).with(flyer.id).exactly(:once)
  end
end
