# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::CreationCommand do
  it 'Poster create produces posters create once after commit' do
    job_owner!('command:posters.create', :oban)
    poster = nil
    expect { poster = create(:poster) }.not_to have_enqueued_job(Posters::CreateJob)
    row = JobOutbox.where(command_type: 'posters.create').sole
    expect(row).to have_attributes(command_version: 1, aggregate_id: poster.id,
                                   dedupe_key: "poster-create:#{poster.id}")
    job_owner!('command:posters.create', :sidekiq)
    clear_enqueued_jobs
    fallback = nil
    expect { fallback = create(:poster) }.to have_enqueued_job(Posters::CreateJob).with(anything).exactly(:once)
    payload = { 'poster_id' => fallback.id, 'user_id' => fallback.user_id, 'locale' => 'en' }
    expect { 3.times { RailsCommands::Registry.handler('posters.created').call(payload) } }
      .not_to have_enqueued_job(Posters::CreateJob)
    native = Poster.insert_all!([{ name: 'Native', user_id: fallback.user_id, status: 0, settings: {},
                                  created_at: Time.current, updated_at: Time.current }]).rows.dig(0, 0)
    payload['poster_id'] = native
    expect { 3.times { RailsCommands::Registry.handler('posters.created').call(payload) } }
      .to have_enqueued_job(Posters::CreateJob).with(native).exactly(:once)
    clear_enqueued_jobs
    expect do
      Poster.transaction do
        create(:poster)
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(Posters::CreateJob)
  end

  it 'creation command payload preserves locale and user scope' do
    job_owner!('command:posters.create', :oban)
    poster = I18n.with_locale(:de) { create(:poster) }
    expect(JobOutbox.where(command_type: 'posters.create').sole.payload)
      .to eq('poster_id' => poster.id, 'user_id' => poster.user_id, 'locale' => 'de')
    payload = { 'poster_id' => poster.id, 'user_id' => poster.user_id + 1, 'locale' => 'de' }
    JobOutbox.delete_all
    expect { RailsCommands::Registry.handler('posters.created').call(payload) }.not_to change(JobOutbox, :count)
  end
end
