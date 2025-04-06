# frozen_string_literal: true

FactoryBot.define do
  factory :import do
    user
    name { 'owntracks_export.json' }
    source { Import.sources[:owntracks] }
  end
end
