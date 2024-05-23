# frozen_string_literal: true

FactoryBot.define do
  factory :point do
    battery_status { 1 }
    ping { 'MyString' }
    battery { 1 }
    topic { 'MyString' }
    altitude { 1 }
    longitude { 'MyString' }
    velocity { 'MyString' }
    trigger { 1 }
    bssid { 'MyString' }
    ssid { 'MyString' }
    connection { 1 }
    vertical_accuracy { 1 }
    accuracy { 1 }
    timestamp { 1 }
    latitude { 'MyString' }
    mode { 1 }
    inrids { 'MyString' }
    in_regions { 'MyString' }
    raw_data { '' }
    tracker_id { 'MyString' }
    import_id { '' }
    city { nil }
    country { nil }
  end
end
