# frozen_string_literal: true

RSpec.configure do |config|
  config.before do
    stub_const('DemoData::PointsSeeder::FIXTURE', Rails.root.join('spec/fixtures/files/demo_data_sample.json.gz'))
  end
end
