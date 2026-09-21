# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Disconnecting a TREK source while its import is running', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
  end

  it 'locks the source row before deleting it so a concurrent import cannot attach a trip' do
    source = create(:trip_source, user:, importing: true)
    create(:trip, user:, trip_source: source, source_identifier: '12', source_status: :active)

    statements = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      statements << payload[:sql]
    end

    begin
      delete settings_trek_source_path(source)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    lock_index = statements.index { |sql| sql.match?(/FROM "trip_sources".*FOR UPDATE/m) }
    delete_index = statements.index { |sql| sql.match?(/DELETE FROM "trip_sources"/) }

    expect(delete_index).to be_present
    expect(lock_index).to be_present
    expect(lock_index).to be < delete_index
  end
end
