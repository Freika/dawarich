FactoryBot.define do
  factory :trip do
    name { "MyString" }
    started_at { "2024-11-27 17:16:21" }
    ended_at { "2024-11-27 17:16:21" }
    notes { "MyText" }
    user { nil }
  end
end
