# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::Archiver do
  let(:user) { create(:user) }

  before do
    create_list(:point, 3, user:, timestamp: Time.utc(2024, 5, 10).to_i)
  end

  it 'creates a verified archive for the month' do
    described_class.new.archive_user(user.id)

    archive = Points::Archive.for_month(user.id, 2024, 5).first
    expect(archive).to be_present
    expect(archive.point_count).to eq(3)
    expect(archive.verified?).to be(true)
    expect(archive.file).to be_attached
  end

  it 'does not delete the points' do
    described_class.new.archive_user(user.id)
    expect(user.points.count).to eq(3)
  end
end
