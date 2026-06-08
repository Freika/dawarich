# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::RestoreUserJob do
  let(:user) { create(:user, points_archive_state: :archived) }

  before do
    create_list(:point, 2, user:, timestamp: Time.utc(2024, 5, 10).to_i)
    Points::Archival::Archiver.new.archive_user(user.id)
    Points::Archive.where(user_id: user.id).update_all(deleted_at: Time.current)
    user.points.delete_all
    user.update!(points_archive_state: :restoring, points_count: 0)
  end

  it 'restores points and returns user to active' do
    described_class.new.perform(user.id)

    expect(user.points.reload.count).to eq(2)
    expect(user.reload.points_archive_state_active?).to be(true)
  end
end
