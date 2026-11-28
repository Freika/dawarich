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

  it "broadcasts the table row with the owner's date and time preferences" do
    user.update!(settings: user.settings.merge('date_format' => 'dd.mm.yyyy', 'time_format' => '12h'))
    service = Imports::Create.new(user, import)

    expect { service.broadcast_status_update }
      .to(have_broadcasted_to(stream_name_from([user, :imports]))
      .with { |payload| expect(payload.to_s).to include('15.07.2026, 12:00 AM') })
  end

  it "broadcasts the deleting row with the owner's date preset" do
    user.update!(settings: user.settings.merge('date_format' => 'yyyy-mm-dd'))

    Imports::DestroyJob.perform_now(import.id)

    expect(broadcasts(stream_name_from([user, :imports])).join).to include('2026-07-15, 00:00')
  end
end
