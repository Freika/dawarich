# frozen_string_literal: true

FactoryBot.define do
  factory :import do
    user
    name { 'APRIL_2013.json' }
    source { Import.sources[:owntracks] }
    raw_data { File.read('spec/fixtures/files/owntracks/2024-03.rec') }
  end
end
