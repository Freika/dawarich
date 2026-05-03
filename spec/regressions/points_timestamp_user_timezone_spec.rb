# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Points-tab timestamps honor the user profile timezone',
               type: :helper do
  helper DatetimeFormattingHelper

  let(:utc_time) { Time.utc(2025, 1, 15, 3, 4, 20) }

  around do |example|
    Time.use_zone('Europe/Berlin') { example.run }
  end

  it 'renders the visible label in the user profile timezone, not Time.zone' do
    rendered = helper.human_datetime_with_seconds(utc_time, 'Australia/Melbourne')

    expect(rendered).to include('14:04:20')
    expect(rendered).not_to include('05:04:20')
  end

  it 'renders the tooltip iso8601 with the user profile offset' do
    rendered = helper.human_datetime_with_seconds(utc_time, 'Australia/Melbourne')

    expect(rendered).to include('+11:00')
    expect(rendered).not_to include('+02:00')
    expect(rendered).not_to include('+01:00')
  end

  it 'falls back to the datetime as-is when no user timezone is given' do
    rendered = helper.human_datetime_with_seconds(utc_time.in_time_zone)

    expect(rendered).to include('04:04:20')
    expect(rendered).to include('+01:00')
  end

  it 'returns nil when the datetime is missing' do
    expect(helper.human_datetime_with_seconds(nil, 'Australia/Melbourne')).to be_nil
  end
end
