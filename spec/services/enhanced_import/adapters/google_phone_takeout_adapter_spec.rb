# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedImport::Adapters::GooglePhoneTakeoutAdapter do
  let(:import) { create(:import, source: :google_phone_takeout) }
  let(:path) { Rails.root.join('spec/fixtures/files/google/timeline_new_format.json').to_s }

  it 'streams visits and tracks without buffering the whole file' do
    expect(Oj).not_to receive(:saj_parse)

    extracted = described_class.new(import, path).translate.to_a

    expect(extracted.map { |item| item.class.name.demodulize }.uniq).to include('Visit')
  end
end
