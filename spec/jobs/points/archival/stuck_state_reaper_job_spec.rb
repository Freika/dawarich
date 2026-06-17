# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::StuckStateReaperJob do
  it 'resets a long-stuck archiving user to active and purges partial archives' do
    user = create(:user, points_archive_state: :archiving)
    create_list(:point, 2, user:, timestamp: Time.utc(2024, 5, 10).to_i)
    Points::Archival::Archiver.new.archive_user(user.id)
    user.update_column(:updated_at, 7.hours.ago)

    described_class.new.perform

    expect(user.reload.points_archive_state_active?).to be(true)
    expect(Points::Archive.where(user_id: user.id, deleted_at: nil)).to be_empty
  end

  it 'resets a long-stuck restoring user to archived' do
    user = create(:user, points_archive_state: :restoring)
    user.update_column(:updated_at, 7.hours.ago)

    described_class.new.perform

    expect(user.reload.points_archive_state_archived?).to be(true)
  end

  it 'leaves a recently transitioned user untouched' do
    user = create(:user, points_archive_state: :restoring)

    described_class.new.perform

    expect(user.reload.points_archive_state_restoring?).to be(true)
  end
end
