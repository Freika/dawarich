# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sidekiq initializer' do
  describe 'source runtime contracts' do
    it 'registers metrics and preserves the 24 cron definitions and ambient firing times' do
      require 'yabeda/sidekiq'
      expect(Yabeda.groups.key?(:sidekiq)).to be true

      schedules = YAML.load_file(Rails.root.join('config/schedule.yml'))
      expect(schedules.size).to eq(24)
      schedules.each_value do |schedule|
        expect(Fugit::Cron.parse(schedule.fetch('cron'))).to be_present
        expect(schedule.fetch('class').constantize < ApplicationJob).to be true
        expect(schedule.fetch('queue')).to be_present
      end

      previous_tz = ENV.fetch('TZ', nil)
      begin
        ENV.delete('TZ')
        Time.use_zone('Europe/Berlin') do
          expect(Fugit::Cron.parse('15 1 * * *').next_time('2026-01-10T00:00:00Z').utc.to_s)
            .to eq('2026-01-10 00:15:00 UTC')
          expect(Fugit::Cron.parse('15 1 * * *').next_time('2026-07-10T00:00:00Z').utc.to_s)
            .to eq('2026-07-10 23:15:00 UTC')
        end
        ENV['TZ'] = 'Asia/Tokyo'
        Time.use_zone('Europe/Berlin') do
          expect(Fugit::Cron.parse('15 1 * * *').next_time('2026-01-10T00:00:00Z').utc.to_s)
            .to eq('2026-01-10 16:15:00 UTC')
        end
        ['', 'Invalid/Zone'].each do |invalid|
          ENV['TZ'] = invalid
          Time.use_zone('Europe/Berlin') do
            expect(Fugit::Cron.parse('15 1 * * *').next_time('2026-01-10T00:00:00Z').utc.to_s)
              .to eq('2026-01-10 00:15:00 UTC')
          end
        end
      ensure
        previous_tz ? ENV['TZ'] = previous_tz : ENV.delete('TZ')
      end
    end
  end
end
