# frozen_string_literal: true

FactoryBot.define do
  factory :notification do
    title { "MyString" }
    content { "MyText" }
    user
    kind { :info }
    read_at { nil }
  end
end
