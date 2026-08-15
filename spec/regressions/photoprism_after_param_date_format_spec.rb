# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Photoprism date filters are sent as plain dates' do
  let(:user) do
    create(
      :user,
      settings: {
        'photoprism_url' => 'http://photoprism.local',
        'photoprism_api_key' => 'test_api_key'
      }
    )
  end

  def stub_empty
    stub_request(:get, /photoprism\.local/).to_return(
      status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  def captured(param)
    value = nil
    expect(WebMock).to(have_requested(:get, /photoprism\.local/).with do |req|
      value ||= req.uri.query_values[param]
      true
    end)
    value
  end

  it 'reduces a minute-precision start_date to the plain after date Photoprism accepts' do
    stub_empty
    Photoprism::RequestPhotos.new(user, start_date: '2026-06-21T00:00+02:00').call
    expect(captured('after')).to eq('2026-06-21')
  end

  it 'sends before as a plain date one day past end_date' do
    stub_empty
    Photoprism::RequestPhotos.new(user, start_date: '2026-06-21', end_date: '2026-06-23T00:00+02:00').call
    expect(captured('before')).to eq('2026-06-24')
  end

  it 'defaults the after date and does not raise when start_date is nil' do
    stub_empty
    expect { Photoprism::RequestPhotos.new(user, start_date: nil).call }.not_to raise_error
    expect(captured('after')).to eq('1970-01-01')
  end

  it 'defaults the after date and does not raise when start_date is blank' do
    stub_empty
    expect { Photoprism::RequestPhotos.new(user, start_date: '').call }.not_to raise_error
    expect(captured('after')).to eq('1970-01-01')
  end

  it 'excludes photos taken after a precise end_date' do
    stub_request(:get, /photoprism\.local/).to_return(
      { status: 200, body: [{ 'TakenAtLocal' => '2026-06-23T18:00:00Z' }].to_json,
        headers: { 'Content-Type' => 'application/json' } },
      { status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' } }
    )

    result = Photoprism::RequestPhotos.new(user, start_date: '2026-06-21', end_date: '2026-06-23T10:00:00Z').call

    expect(result).to be_empty
  end
end
