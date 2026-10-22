# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Invalid visit time range reporting' do
  let(:user) { create(:user) }
  let(:params) do
    {
      name: 'Test Visit',
      latitude: 52.52,
      longitude: 13.405,
      started_at: '2025-06-21T18:42:00Z',
      ended_at: '2025-06-21T18:41:00Z'
    }
  end

  it 'returns validation feedback without reporting an application exception' do
    service = Visits::Create.new(user, params)

    expect(ExceptionReporter).not_to receive(:call)
    expect(service.call).to be(false)
    expect(service.errors).to include('ended_at must be after started_at')
    expect(user.visits).to be_empty
  end

  it 'handles malformed timestamps without reporting an application exception' do
    service = Visits::Create.new(user, params.merge(started_at: 'not-a-date'))

    expect(ExceptionReporter).not_to receive(:call)
    expect(service.call).to be(false)
    expect(service.errors).to include('invalid timestamps')
    expect(user.visits).to be_empty
  end

  it 'rejects impossible calendar timestamps without reporting them' do
    service = Visits::Create.new(user, params.merge(started_at: '2025-02-30T12:00:00Z'))

    expect(ExceptionReporter).not_to receive(:call)
    expect(service.call).to be(false)
    expect(service.errors).to include('invalid timestamps')
    expect(user.visits).to be_empty
  end
end
