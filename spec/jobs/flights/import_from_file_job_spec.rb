# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::ImportFromFileJob, type: :job do
  let(:user) { create(:user) }
  let(:json_string) { file_fixture('air_trail/export_v3.json').read }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(json_string),
      filename: 'airtrail.json',
      content_type: 'application/json'
    )
  end

  it 'imports flights and notifies the user' do
    described_class.perform_now(user.id, blob.id)

    expect(user.flights.count).to eq(1)
    notification = user.notifications.last
    expect(notification.kind).to eq('info')
    expect(notification.content).to include('1 created')
  end

  it 'purges the blob after a successful import' do
    blob_id = blob.id

    described_class.perform_now(user.id, blob_id)

    expect(ActiveStorage::Blob.exists?(blob_id)).to be false
  end

  it 'notifies the user on parser errors without raising' do
    bad_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('not json'),
      filename: 'bad.json',
      content_type: 'application/json'
    )

    expect { described_class.perform_now(user.id, bad_blob.id, 'airtrail_json') }
      .not_to raise_error

    notification = user.notifications.last
    expect(notification.kind).to eq('error')
    expect(notification.content).to include('Invalid JSON')
  end

  it 'purges the blob after a parser error' do
    bad_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('not json'),
      filename: 'bad.json',
      content_type: 'application/json'
    )
    blob_id = bad_blob.id

    described_class.perform_now(user.id, blob_id, 'airtrail_json')

    expect(ActiveStorage::Blob.exists?(blob_id)).to be false
  end

  it 'notifies the user on validation errors without raising' do
    invalid_flight = Flight.new
    invalid_flight.valid?
    import = instance_double(Flights::ImportFromFile)
    allow(Flights::ImportFromFile).to receive(:new).and_return(import)
    allow(import).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(invalid_flight))

    expect { described_class.perform_now(user.id, blob.id) }.not_to raise_error

    notification = user.notifications.last
    expect(notification.kind).to eq('error')
    expect(notification.title).to eq('Flight import failed')
    expect(notification.content).to include('Validation failed')
    expect(ActiveStorage::Blob.exists?(blob.id)).to be false
  end

  it 'no-ops for a missing user' do
    expect { described_class.perform_now(-1, blob.id) }.not_to raise_error
  end

  it 'no-ops for a missing blob' do
    expect { described_class.perform_now(user.id, -1) }.not_to raise_error
  end
end
