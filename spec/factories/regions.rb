# frozen_string_literal: true

FactoryBot.define do
  factory :region do
    sequence(:code) { |n| "TT-#{n.to_s.rjust(2, '0')}" }
    geom { 'MULTIPOLYGON (((0 0, 0 1, 1 1, 1 0, 0 0)))' }
  end
end
