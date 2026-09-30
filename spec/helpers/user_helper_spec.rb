# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserHelper, type: :helper do
  describe '#settings_time_zone_options' do
    it 'lists each IANA zone once with its offset, sorted by the offset' do
      options = helper.settings_time_zone_options
      seconds = options.map { |_, iana| ActiveSupport::TimeZone[iana].utc_offset }

      expect(options).to include(['(GMT+09:00) Asia/Tokyo', 'Asia/Tokyo'])
      expect(options.map(&:last)).to eq(options.map(&:last).uniq)
      expect(options.map(&:first)).to all(match(/\A\(GMT[+-]\d\d:\d\d\) \S+\z/))
      expect(seconds).to eq(seconds.sort)
    end
  end
end
