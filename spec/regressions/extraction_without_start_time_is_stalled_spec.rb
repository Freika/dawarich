# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'An in-flight extraction without a readable start time can be started over' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }

  def extraction(status, payload)
    import.update_columns(
      additional_data_extraction_status: Import.additional_data_extraction_statuses[status],
      additional_data_extraction: payload
    )
    import
  end

  it 'treats a queued run with no start time as stalled' do
    expect(extraction(:pending, {}).extraction_stalled?).to be(true)
  end

  it 'treats a run whose start time is not a time as stalled' do
    expect(extraction(:running, { 'started_at' => 'not a time' }).extraction_stalled?).to be(true)
  end

  it 'treats a run whose start time is out of range as stalled' do
    expect(extraction(:running, { 'started_at' => '2026-99-99T00:00:00Z' }).extraction_stalled?).to be(true)
  end

  it 'keeps a fresh run in flight' do
    expect(extraction(:running, { 'started_at' => 5.minutes.ago.iso8601 }).extraction_stalled?).to be(false)
  end

  it 'never calls a finished run stalled' do
    expect(extraction(:completed, {}).extraction_stalled?).to be(false)
  end

  it 'offers Start over on the extraction card' do
    extraction(:pending, {})
    rendered = ApplicationController.render(partial: 'imports/extraction_card', locals: { import: import })

    expect(rendered).to include(I18n.t('imports.extraction_card.start_over'))
  end
end
