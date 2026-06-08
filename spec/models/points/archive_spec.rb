# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archive do
  it 'belongs to a user' do
    expect(create(:points_archive).user).to be_present
  end

  it 'requires year, month, chunk_number, point_count, checksum' do
    archive = described_class.new(chunk_number: nil)
    archive.valid?
    expect(archive.errors.attribute_names).to include(:year, :month, :chunk_number, :point_count, :point_ids_checksum)
  end

  it 'builds the storage key from user/year/month/chunk' do
    archive = build(:points_archive, user_id: 7, year: 2024, month: 5, chunk_number: 2)
    expect(archive.storage_key).to eq('points_archives/7/2024/05/002.jsonl.gz.enc')
  end

  it 'reports verified? based on verified_at' do
    expect(build(:points_archive, verified_at: nil).verified?).to be(false)
    expect(build(:points_archive, verified_at: Time.current).verified?).to be(true)
  end
end
