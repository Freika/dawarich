# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Poster, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(created: 0, processing: 1, completed: 2, failed: 3) }
  end

  describe 'job enqueueing' do
    it 'enqueues a generation job on create' do
      expect do
        create(:poster)
      end.to have_enqueued_job(Posters::CreateJob).on_queue('posters')
    end
  end

  describe 'status broadcasts' do
    include ActionCable::TestHelper
    include Turbo::Streams::StreamName

    it 'broadcasts a card replace to the owner posters stream on update' do
      poster = create(:poster)

      expect { poster.update!(status: :completed) }
        .to have_broadcasted_to(stream_name_from([poster.user, :posters]))
    end
  end
end
