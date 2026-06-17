# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'points.lonlat NOT NULL database constraint' do
  let(:user) { create(:user) }

  it 'rejects inserting a point without coordinates' do
    expect do
      ActiveRecord::Base.connection.execute(
        'INSERT INTO points ("timestamp", user_id, created_at, updated_at) ' \
        "VALUES (1, #{user.id}, NOW(), NOW())"
      )
    end.to raise_error(ActiveRecord::NotNullViolation)
  end
end
