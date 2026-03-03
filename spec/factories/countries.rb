# frozen_string_literal: true

FactoryBot.define do
  factory :country do
    name { 'Serranilla Bank' }
    iso_a2 { 'SB' }
    iso_a3 { 'SBX' }
    geom do
      'MULTIPOLYGON (((-78.637074 15.862087, -78.640411 15.864, -78.636871 15.867296, -78.637074 15.862087)))'
    end
  end
end
