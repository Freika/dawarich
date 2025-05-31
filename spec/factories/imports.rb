# frozen_string_literal: true

FactoryBot.define do
  factory :import do
    user
    name { 'owntracks_export.json' }
    source { Import.sources[:owntracks] }

    trait :with_points do
      after(:create) do |import|
        create_list(:point, 10, import:)
      end
    end
  end
end
