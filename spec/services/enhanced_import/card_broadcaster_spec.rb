# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedImport::CardBroadcaster do
  include ActionCable::TestHelper

  let(:user) { create(:user) }
  let(:import) { create(:import, user: user) }

  it 'broadcasts the card and swallows a render error' do
    expect { described_class.call(import) }.to have_broadcasted_to("import_#{import.id}_extraction")

    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, 'boom')
    allow(Rails.logger).to receive(:warn)

    expect { described_class.call(import) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/card broadcast failed import_id=#{import.id}/)
  end
end
