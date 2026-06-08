# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::DeleteSweepJob do
  let(:user) { create(:user, points_archive_state: :archived) }

  before do
    create_list(:point, 3, user:, timestamp: Time.utc(2024, 5, 10).to_i)
    Points::Archival::Archiver.new.archive_user(user.id)
    Points::Archive.where(user_id: user.id).update_all(verified_at: 30.days.ago)
  end

  it 'deletes rows for cooled, re-verified archives and zeroes the counter' do
    user.update_column(:points_count, 3)

    described_class.new.perform

    expect(user.points.reload.count).to eq(0)
    expect(user.reload.points_count).to eq(0)
    expect(Points::Archive.where(user_id: user.id).first.deleted_at).to be_present
  end

  it 'refuses to delete when the archive no longer verifies' do
    Points::Archive.where(user_id: user.id).find_each { |a| a.file.purge }

    described_class.new.perform
    expect(user.points.reload.count).to eq(3)
  end

  it 'does not delete for a user who is no longer archived (e.g. restoring)' do
    user.update!(points_archive_state: :restoring)
    described_class.new.perform
    expect(user.points.reload.count).to eq(3)
    expect(Points::Archive.where(user_id: user.id).first.deleted_at).to be_nil
  end
end
