# frozen_string_literal: true

FactoryBot.define do
  factory :export do
    name { 'export' }
    status { :created }
    file_format { :json }
    user
  end
end
