# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Extraction availability is resolved when an import is created' do
  let(:user) { create(:user) }

  it 'marks a source without an adapter as unsupported' do
    import = create(:import, user: user, source: :kml)

    expect(import.additional_data_extraction_unsupported?).to be true
  end

  it 'marks an import with no source as unsupported' do
    import = create(:import, user: user, source: nil)

    expect(import.additional_data_extraction_unsupported?).to be true
  end

  it 'leaves a supported source available for extraction' do
    import = create(:import, user: user, source: :google_phone_takeout)

    expect(import.additional_data_extraction_not_attempted?).to be true
  end

  it 'becomes available again once a source-less upload is identified as supported' do
    import = create(:import, user: user, source: nil)
    expect(import.additional_data_extraction_unsupported?).to be true

    import.update!(source: :google_phone_takeout)

    expect(import.additional_data_extraction_not_attempted?).to be true
  end

  it 'keeps a finished extraction when the source is rewritten' do
    import = create(:import, user: user, source: :google_phone_takeout)
    import.update_columns(
      additional_data_extraction_status: Import.additional_data_extraction_statuses[:completed]
    )

    import.reload.update!(name: 'renamed.json')

    expect(import.reload.additional_data_extraction_completed?).to be true
  end

  it 'does not offer the extraction call to action for an unsupported import' do
    import = create(:import, user: user, source: :kml)

    rendered = ApplicationController.render(
      partial: 'imports/extraction_card',
      locals: { import: import }
    )

    expect(rendered).not_to include('Extract additional data')
    expect(rendered).to include('nothing additional to extract')
  end

  describe 'a run that never reported back' do
    let(:import) { create(:import, user: user, source: :google_phone_takeout) }

    it 'is not stalled while it is still fresh' do
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:running],
        additional_data_extraction: { 'started_at' => 5.minutes.ago.iso8601 }
      )

      expect(import.extraction_stalled?).to be false
    end

    it 'is stalled once it outlives the window, so the card can offer recovery' do
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:running],
        additional_data_extraction: { 'started_at' => 7.hours.ago.iso8601 }
      )

      expect(import.extraction_stalled?).to be true

      rendered = ApplicationController.render(partial: 'imports/extraction_card', locals: { import: import })
      expect(rendered).to include('Start over')
    end

    it 'is never stalled when nothing is running' do
      expect(import.extraction_stalled?).to be false
    end
  end
end
