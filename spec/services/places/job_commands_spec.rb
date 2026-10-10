# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Places::JobCommands' do
  it 'old place jobs forward and pending commands rehome with original arguments' do
    user = create(:user)
    other = create(:user)
    place = create(:place, user: user, source: :photon, name: Place::DEFAULT_NAME)
    foreign = create(:place, user: other, source: :photon)
    orphan = create(:place, user: user, source: :photon)
    JobOutbox.delete_all
    clear_enqueued_jobs
    types = %w[places.name_fetch places.delete_if_orphan places.orphan_cleanup places.bulk_name_fetch]
    types.each { job_owner!("command:#{_1}", :oban) }
    jobs = [Places::NameFetchingJob.new(place.id), Places::DeleteIfOrphanJob.new(orphan.id),
            Places::OrphanCleanupJob.new(user.id), Places::BulkNameFetchingJob.new]
    args = [[place.id], [orphan.id], [user.id], []]
    2.times { jobs.zip(args).each { |job, arguments| job.perform(*arguments) } }
    expect(Place.exists?(orphan.id)).to be(true)
    expect(place.reload.name).to eq(Place::DEFAULT_NAME)
    expect(JobOutbox.pending.count).to eq(4)
    expect(JobOutbox.pending.find_by!(command_type: 'places.name_fetch').payload)
      .to eq('user_id' => user.id, 'place_id' => place.id)
    expect(JobOutbox.pending.find_by!(command_type: 'places.bulk_name_fetch').payload).to eq({})
    due = 1.hour.from_now.change(usec: 0)
    JobOutbox.pending.update_all(scheduled_at: due)
    types.each do |type|
      job_owner!("command:#{type}", :sidekiq)
      JobCommands.rehome!(type, by: 'a12d2-spec')
    end
    expect(JobOutbox.pending.count).to eq(0)
    jobs.zip(args).each { |job, arguments| expect(job.class).to have_been_enqueued.with(*arguments).at(due) }
    clear_enqueued_jobs
    RailsCommands::Registry.handler('place_name_fetch').call('user_id' => user.id, 'place_id' => foreign.id)
    orphan_handler = RailsCommands::Registry.handler('places_delete_if_orphan')
    orphan_handler.call('user_id' => user.id, 'place_ids' => [foreign.id, orphan.id])
    expect(Places::NameFetchingJob).not_to have_been_enqueued
    expect(Places::DeleteIfOrphanJob).to have_been_enqueued.with(orphan.id).exactly(:once)
    expect(Places::DeleteIfOrphanJob).not_to have_been_enqueued.with(foreign.id)
    clear_enqueued_jobs
    RailsCommands::Registry.handler('places_orphan_cleanup').call('user_id' => user.id)
    RailsCommands::Registry.handler('places_bulk_name_fetch').call({})
    expect(Places::OrphanCleanupJob).to have_been_enqueued.with(user.id)
    expect(Places::BulkNameFetchingJob).to have_been_enqueued.with(no_args)
    clear_enqueued_jobs
    RailsCommands::Registry.handler('places_orphan_cleanup').call('user_id' => user.id,
                                                                  'scheduled_at' => due.iso8601(6))
    expect(Places::OrphanCleanupJob).to have_been_enqueued.with(user.id).at(due)
    job_owner!('command:places.name_fetch', :oban)
    RailsCommands::Registry.handler('place_name_fetch').call('user_id' => user.id, 'place_id' => place.id)
    expect(JobOutbox.pending.sole).to have_attributes(command_type: 'places.name_fetch')
    expect(Places::NameFetchingJob).not_to have_been_enqueued
    expect { Places::NameFetchingJob.new.perform(-1) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
