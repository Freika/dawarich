# frozen_string_literal: true

require 'active_support/testing/time_helpers'
time_helpers = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
instants = [Time.utc(2026, 1, 19, 10), Time.utc(2026, 7, 19, 10)]
clocks = %w[UTC Etc/UTC Europe/London Africa/Accra Europe/Berlin].product(instants).map do |zone, clock|
  stamp = time_helpers.travel_to(clock) { Time.use_zone(zone) { Time.current.iso8601 } }
  { zone: zone, utc: clock.iso8601, stamp: stamp }
end
cases = ['Đắk Lắk', 'Łódź', 'Curaçao', "e\u0301", "\u0301", '中文', ' Æ Ø Œ ß '].map do |text|
  { text: text, expected: I18n.with_locale(:en) { I18n.transliterate(text).downcase } }
end
fixtures = Rails.root.join('app-phoenix/test/fixtures/achievements_ui/text.json')
File.write(fixtures, JSON.pretty_generate(clocks: clocks, search: cases))
puts JSON.generate(clocks: clocks.size, cases: cases.size)
