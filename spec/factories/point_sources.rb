# frozen_string_literal: true

FactoryBot.define do
  factory :point_source do
    sequence(:digest) { |n| Digest::MD5.hexdigest("point-source-#{n}") }
    tracker_id { 'pixel-8' }
    topic { 'owntracks/user/pixel-8' }
    ssid { 'home-wifi' }
    bssid { 'aa:bb:cc:dd:ee:ff' }
    connection { 'wifi' }
    trigger { 'manual_event' }
    battery_status { 'unplugged' }
    inrids { [] }
    in_regions { [] }
  end
end
