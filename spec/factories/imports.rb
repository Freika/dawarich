# frozen_string_literal: true

FactoryBot.define do
  factory :import do
    user
    sequence(:name) { |n| "owntracks_export_#{n}.json" }
    # source { Import.sources[:owntracks] }

    trait :with_points do
      after(:create) do |import|
        create_list(:point, 10, import:)
      end
    end
  end
end
