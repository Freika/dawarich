# frozen_string_literal: true

FactoryBot.define do
  factory :points_archive, class: 'Points::Archive' do
    user
    year { 2024 }
    month { 5 }
    chunk_number { 1 }
    point_count { 10 }
    point_ids_checksum { Digest::SHA256.hexdigest('1,2,3') }
    archived_at { Time.current }
    metadata { { 'format_version' => 2 } }
  end
end
