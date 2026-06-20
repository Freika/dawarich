# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Archival::AdvisoryLock do
  it 'returns the block value' do
    expect(described_class.with_lock(1) { 7 }).to eq(7)
  end

  it 'runs the block inside a transaction so a raise rolls back the work' do
    user = create(:user)

    expect do
      described_class.with_lock(user.id) do
        user.update!(email: 'changed@example.com')
        raise 'boom'
      end
    end.to raise_error('boom')

    expect(user.reload.email).not_to eq('changed@example.com')
  end
end
