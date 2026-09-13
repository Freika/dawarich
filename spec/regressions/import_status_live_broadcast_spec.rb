# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import status live broadcast outside a request context' do
  include ActionCable::TestHelper
  include Turbo::Streams::StreamName

  let(:user) do
    create(:user).tap { |u| u.update!(settings: u.settings.to_h.merge('timezone' => 'Pacific/Auckland')) }
  end
  let(:import) do
    create(:import, user: user, status: 'processing', created_at: Time.utc(2026, 7, 14, 12, 0))
  end

  it 'broadcasts the table row with the created time in the user timezone' do
    service = Imports::Create.new(user, import)

    expect { service.broadcast_status_update }
      .to(have_broadcasted_to(stream_name_from([user, :imports]))
      .with { |payload| expect(payload.to_s).to include('15 Jul 2026, 00:00') })
  end
end
