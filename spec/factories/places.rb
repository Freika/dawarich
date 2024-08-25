# frozen_string_literal: true

FactoryBot.define do
  factory :place do
    name { 'MyString' }
    latitude { 1.5 }
    longitude { 1.5 }
  end
end
