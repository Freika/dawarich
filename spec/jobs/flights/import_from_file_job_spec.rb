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

  it 'notifies the user and re-raises on parser errors' do
    bad_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('not json'),
      filename: 'bad.json',
      content_type: 'application/json'
    )

    expect { described_class.perform_now(user.id, bad_blob.id, 'airtrail_json') }
      .to raise_error(Flights::Parsers::Error)

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

    expect { described_class.perform_now(user.id, blob_id, 'airtrail_json') }
      .to raise_error(Flights::Parsers::Error)

    expect(ActiveStorage::Blob.exists?(blob_id)).to be false
  end

  it 'no-ops for a missing user' do
    expect { described_class.perform_now(-1, blob.id) }.not_to raise_error
  end

  it 'no-ops for a missing blob' do
    expect { described_class.perform_now(user.id, -1) }.not_to raise_error
  end
end
