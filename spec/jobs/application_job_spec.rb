# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationJob do
  # Create a concrete subclass to test the helper
  let(:job) { Class.new(described_class).new }

  describe '#find_non_deleted_user' do
    context 'when user exists and is active' do
      let(:user) { create(:user) }

      it 'returns the user' do
        expect(job.find_non_deleted_user(user.id)).to eq(user)
      end
    end

    context 'when user is soft-deleted' do
      let(:user) { create(:user) }

      before { user.mark_as_deleted! }

      it 'returns nil' do
        expect(job.find_non_deleted_user(user.id)).to be_nil
      end
    end

    context 'when user does not exist' do
      it 'returns nil' do
        expect(job.find_non_deleted_user(999_999)).to be_nil
      end
    end
  end
end
