# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Self-hosted instances and analytics', type: :request do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    stub_const('ENV', ENV.to_hash.merge('PARTNERO_PROGRAM_ID' => 'PROG123', 'GOOGLE_ADS_ID' => 'AW-123'))
  end

  it 'renders no tracker, advertising id or consent prompt' do
    get new_user_session_path

    %w[posthog rybbit simpleanalytics googletagmanager partnero brevo PROG123 AW-123
       product-analytics-choice].each do |marker|
      expect(response.body).not_to include(marker)
    end
  end
end
