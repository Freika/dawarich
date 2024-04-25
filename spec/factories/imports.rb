# frozen_string_literal: true

FactoryBot.define do
  factory :import do
    user
    name { 'APRIL_2013.json' }
    source { 1 }
    raw_data { JSON.parse(File.read('spec/fixtures/files/owntracks/export.json')) }
  end
end
