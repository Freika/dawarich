# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Points archival restore-on-return', type: :request do
  let(:user) { create(:user, points_archive_state: :archived) }

  before { sign_in user }

  it 'enqueues a restore and flips the user to restoring on first request' do
    expect { get root_path }.to have_enqueued_job(Points::Archival::RestoreUserJob).with(user.id)
    expect(user.reload.points_archive_state_restoring?).to be(true)
  end

  it 'does not re-enqueue while already restoring' do
    user.update!(points_archive_state: :restoring)
    expect { get root_path }.not_to have_enqueued_job(Points::Archival::RestoreUserJob)
  end

  it 'rolls the user back to archived if enqueuing the restore fails' do
    allow(Points::Archival::RestoreUserJob).to receive(:perform_later).and_raise(StandardError, 'queue down')

    get root_path

    expect(user.reload.points_archive_state_archived?).to be(true)
  end

  context 'when authenticated via API key' do
    let(:api_user) { create(:user, points_archive_state: :archived) }

    it 'enqueues a restore and flips the user to restoring on first API request' do
      expect do
        get api_v1_areas_url, headers: { 'Authorization' => "Bearer #{api_user.api_key}" }
      end.to have_enqueued_job(Points::Archival::RestoreUserJob).with(api_user.id)
      expect(api_user.reload.points_archive_state_restoring?).to be(true)
    end
  end
end
