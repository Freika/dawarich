# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map v2 date pickers reflect the time component from the URL', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'renders the start_at datetime-local input with the requested time, not just the date' do
    get map_v2_path(start_at: '2026-07-11T14:30:00Z', end_at: '2026-07-11T18:45:00Z')

    expect(response).to have_http_status(:ok)

    input = response.body[/<input[^>]*name="start_at"[^>]*>/]
    value = input && input[/value="([^"]*)"/, 1]

    expect(value).to be_present, 'no start_at datetime-local input found'
    expect(value).to match(/T14:30/), "start_at picker value was #{value.inspect} (time component missing)"
  end
end
