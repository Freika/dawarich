# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::Restorer do
  it 'keeps the archive when a row cannot be re-inserted due to a unique collision' do
    user = create(:user)
    create(:point, user:, longitude: 13.40, latitude: 52.52, timestamp: 1_700_000_000)
    create(:point, user:, longitude: 13.41, latitude: 52.53, timestamp: 1_700_000_100)
    Points::Archival::Archiver.new.archive_user(user.id)
    user.points.delete_all
    create(:point, user:, longitude: 13.40, latitude: 52.52, timestamp: 1_700_000_000)

    described_class.new.restore_user(user.id)

    expect(Points::Archive.where(user_id: user.id)).to exist
    expect(user.points.reload.count).to eq(2)
  end
end
