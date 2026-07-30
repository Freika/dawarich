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
    expect(service.errors).to include('Ended at must be greater than')
    expect(user.visits).to be_empty
  end
end
