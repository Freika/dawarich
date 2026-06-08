# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::Restorer do
  let(:user) { create(:user) }

  before do
    create_list(:point, 3, user:, timestamp: Time.utc(2024, 5, 10).to_i)
    Points::Archival::Archiver.new.archive_user(user.id)
  end

  it 'restores deleted rows with original ids and geometry' do
    original = user.points.order(:id).map { |p| [p.id, p.lonlat.x, p.lonlat.y] }
    user.points.delete_all

    described_class.new.restore_user(user.id)

    restored = user.points.reload.order(:id).map { |p| [p.id, p.lonlat.x, p.lonlat.y] }
    expect(restored).to eq(original)
  end

  it 'recomputes users.points_count' do
    user.points.delete_all
    user.update_column(:points_count, 0)

    described_class.new.restore_user(user.id)
    expect(user.reload.points_count).to eq(3)
  end
end
