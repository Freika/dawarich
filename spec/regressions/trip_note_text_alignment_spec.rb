# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'trips/notes/_note', type: :view do
  it 'renders the note body without template indentation' do
    trip = build_stubbed(:trip)
    note = build_stubbed(:note, attachable: trip, body: "Test 1\nText 1\nText 2")

    render partial: 'trips/notes/note', locals: { note:, trip: }

    body = rendered.match(%r{whitespace-pre-wrap[^>]*>(.*?)</div>}m)[1]
    expect(body).to eq("Test 1\nText 1\nText 2")
  end
end
