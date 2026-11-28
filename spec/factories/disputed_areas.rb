# frozen_string_literal: true

FactoryBot.define do
  factory :disputed_area do
    name { 'Test zone' }
    geom { 'POLYGON ((0 0, 0 1, 1 1, 1 0, 0 0))' }
  end
end
