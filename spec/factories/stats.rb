# frozen_string_literal: true

FactoryBot.define do
  factory :stat do
    year { 1 }
    month { 1 }
    distance { 1000 } # 1 km
    user
    toponyms do
      [
        {
          'cities' => [
            { 'city' => 'Moscow', 'points' => 7, 'timestamp' => 1_554_317_696, 'stayed_for' => 1831 }
          ],
          'country' => 'Russia'
        }, { 'cities' => [], 'country' => nil }
      ]
    end
  end
end
