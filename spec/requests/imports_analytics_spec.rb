# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import analytics events', type: :request do
  let(:user) { create(:user) }
  let(:file) { fixture_file_upload('owntracks/2024-03.rec', 'text/plain') }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: file.open, filename: file.original_filename,
                                           content_type: file.content_type)
  end
  let(:signed_id) { blob.signed_id }

  def import_started_signals
    Nokogiri::HTML(response.body).css('[data-controller="analytics-event"][data-analytics-event-name-value="import_started"]')
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    sign_in user
  end

  it 'hands the next page a single import_started signal for an accepted import' do
    post imports_path, params: { import: { source: 'owntracks', files: [signed_id] } }
    follow_redirect!

    expect(import_started_signals.size).to eq(1)
    expect(JSON.parse(import_started_signals.first['data-analytics-event-props-value'])).to eq('files' => 1)

    get imports_path
    expect(import_started_signals).to be_empty
  end

  it 'counts an upload of several files as one import_succeeded' do
    second_blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join('spec/fixtures/files/owntracks/2023-02_old.rec')),
      filename: '2023-02_old.rec', content_type: 'text/plain'
    )
    post imports_path, params: { import: { source: 'owntracks', files: [signed_id, second_blob.signed_id] } }

    first, second = user.imports.order(:id).to_a
    [first, second].each do |import|
      import.update!(status: :completed)
      create(:point, user:, import:)
      Analytics::ImportSucceeded.new(import).call
    end

    expect(AnalyticsEvent.event_import_succeeded.sole.properties).to eq('result' => 'complete', 'files' => 2)
  end

  it 'sends no signal when no file was accepted' do
    post imports_path, params: { import: { source: 'owntracks', files: ['not-a-signed-id'] } }
    get imports_path

    expect(import_started_signals).to be_empty
  end

  it 'sends no signal on self-hosted instances' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    post imports_path, params: { import: { source: 'owntracks', files: [signed_id] } }
    follow_redirect!

    expect(import_started_signals).to be_empty
  end
end
