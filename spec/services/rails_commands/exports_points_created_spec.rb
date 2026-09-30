# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsCommands exports.points_created' do
  let(:user) { create(:user) }
  let(:export) { insert_export(user) }

  def insert_export(owner)
    Export.insert_all([{ user_id: owner.id, name: 'export_from_2024-03-01_to_2024-03-31.json', status: 0,
                         file_format: 0, file_type: 0, start_at: Time.utc(2024, 2, 29, 23),
                         end_at: Time.utc(2024, 3, 30, 23), created_at: Time.current, updated_at: Time.current }])
    owner.exports.order(:id).last
  end

  def payload = { 'export_id' => export.id, 'user_id' => user.id, 'locale' => 'de' }
  def run(value = payload) = RailsCommands::Registry.handler('exports.points_created').call(value)

  it 'enqueues the ExportJob that Export#after_create enqueues, in the locale of the request' do
    I18n.with_locale(:de) { user.exports.create!(name: 'rails.json', status: :created, file_format: :json) }
    rails_job = enqueued_jobs.sole
    clear_enqueued_jobs

    run

    job = enqueued_jobs.sole
    expect([job[:job], job[:queue], job['locale']]).to eq([rails_job[:job], rails_job[:queue], rails_job['locale']])
    expect(rails_job['locale']).to eq('de')
    expect(job[:args]).to eq([export.id])
  end

  it 'writes one pending exports.points outbox command instead once Oban owns the key' do
    job_owner!('command:exports.points', :oban)

    2.times { run }

    expect(enqueued_jobs).to be_empty
    expect(JobOutbox.sole.attributes.slice('command_type', 'command_version', 'payload', 'aggregate_id',
                                           'dedupe_key', 'state'))
      .to eq('command_type' => 'exports.points', 'command_version' => 1,
             'payload' => { 'export_id' => export.id, 'user_id' => user.id }, 'aggregate_id' => export.id,
             'dedupe_key' => "points-export:#{export.id}", 'state' => 'pending')
  end

  it "does nothing for an export that is gone, already claimed or not the payload user's" do
    run(payload.merge('user_id' => create(:user).id))
    run(payload.merge('export_id' => export.id + 1_000_000))
    export.update_columns(status: Export.statuses[:processing])
    run

    expect(enqueued_jobs).to be_empty
  end

  it 'runs through the poller like every other kind' do
    phoenix_tables!
    sql = ActiveRecord::Base.sanitize_sql_array(
      ['INSERT INTO phoenix.rails_commands (kind, payload) VALUES (?, ?::jsonb)', 'exports.points_created',
       payload.to_json]
    )
    ActiveRecord::Base.connection.execute(sql)

    expect(RailsCommands::Poller.drain_once).to eq(1)
    expect(enqueued_jobs.map { _1[:job] }).to eq([ExportJob])
    expect(ActiveRecord::Base.connection.select_value('SELECT count(*) FROM phoenix.rails_commands')).to eq(0)
  end
end
