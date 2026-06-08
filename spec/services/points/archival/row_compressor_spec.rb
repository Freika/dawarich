# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::RowCompressor do
  let(:user) { create(:user) }
  let!(:points) { create_list(:point, 3, user:) }

  it 'gzips all rows as JSONL and reports count' do
    result = described_class.new(Point.where(user_id: user.id)).compress

    raw = Zlib::GzipReader.new(StringIO.new(result[:data])).read
    expect(raw.each_line.count).to eq(3)
    expect(result[:count]).to eq(3)
  end
end
