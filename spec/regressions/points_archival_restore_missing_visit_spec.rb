# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::Restorer do
  it 'nulls visit_id for points whose visit was deleted before restore' do
    user = create(:user)
    visit = create(:visit, user:)
    create_list(:point, 2, user:, visit:, timestamp: Time.utc(2024, 5, 10).to_i)
    Points::Archival::Archiver.new.archive_user(user.id)
    user.points.delete_all
    Visit.where(id: visit.id).delete_all

    expect { described_class.new.restore_user(user.id) }.not_to raise_error
    expect(user.points.reload.count).to eq(2)
    expect(user.points.where.not(visit_id: nil)).to be_empty
  end
end
