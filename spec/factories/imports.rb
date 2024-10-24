# frozen_string_literal: true

FactoryBot.define do
  factory :import do
    user
    name { 'MARCH_2024.json' }
    source { Import.sources[:owntracks] }
    raw_data { OwnTracks::RecParser.new(File.read('spec/fixtures/files/owntracks/2024-03.rec')).call }
  end
end
