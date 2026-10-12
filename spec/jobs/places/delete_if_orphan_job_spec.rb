# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::DeleteIfOrphanJob do
  let(:user) { create(:user) }

  it 'delegates to Places::DeleteIfOrphan and returns its result' do
    place = create(:place, user: user, source: :photon)

    expect { described_class.perform_now(place.id) }
      .to change { Place.exists?(place.id) }.from(true).to(false)
  end

  it 'is a no-op when the place was already deleted (idempotent retry)' do
    expect { described_class.perform_now(999_999) }.not_to raise_error
  end
end
