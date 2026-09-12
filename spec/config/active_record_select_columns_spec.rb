# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Active Record select columns' do
  it 'enumerates model columns instead of selecting every column with a wildcard' do
    sql = Family.where(id: 1).to_sql

    expect(sql).to include('"families"."id"')
    expect(sql).not_to include('"families".*')
  end
end
