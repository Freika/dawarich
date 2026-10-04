# frozen_string_literal: true

require 'rails_helper'
require_relative 'user_data_fixtures_support'

RSpec.describe 'Phoenix fixtures: Rails user data' do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false

  before do
    allow(Rails.application).to receive(:secret_key_base).and_return(A12bFixtureSupport::SECRET)
  end

  around do |example|
    Time.use_zone('UTC') { travel_to(Time.utc(2026, 10, 2, 12)) { example.run } }
  end

  it 'records every user-data entity and both reader versions' do
    result = UserDataFixturesSupport.capture
    expect(result.fetch('sections')).to contain_exactly(
      'settings', 'areas', 'imports', 'exports', 'trips', 'notifications', 'places', 'tags',
      'taggings', 'points', 'visits', 'stats', 'tracks', 'digests', 'raw_data_archives'
    )
    expect(result.fetch('versions')).to eq([1, 2])
    expect(result.fetch('restores').fetch('v2').fetch('result')).to include(
      'points_created' => 3, 'tracks_created' => 1, 'raw_data_archives_created' => 1
    )
    expect(result.fetch('restores').fetch('v1_reversed').fetch('result')).to include('points_created' => 3)
    expect(result.fetch('restores').fetch('v2_repeat').fetch('result')).to include('points_created' => 0)
    expect(result.fetch('boundaries').map { |row| row.fetch('count') }).to eq([4999, 5000, 5001])
    result.fetch('boundaries').each do |row|
      expect(row.fetch('result')).to include('points_created' => row['count'], 'places_created' => row['count'],
                                             'visits_created' => row['count'])
    end
    expect(result.fetch('cases').fetch('transaction_error').fetch('error').fetch('class'))
      .to eq('ActiveModel::UnknownAttributeError')
    expect(result.fetch('cases').fetch('transaction_error').fetch('settings').fetch('timezone')).to eq('UTC')
    expect(result.fetch('cases').fetch('dropped_columns').fetch('result').fetch('points_created')).to eq(1)
    expect(result.fetch('cases').fetch('missing_files').fetch('result').fetch('files_restored')).to eq(0)
    expect(result.fetch('export_errors').fetch('missing_attachment').fetch('status')).to eq('completed')
    expect(result.fetch('export_errors').fetch('missing_attachment').fetch('imports').first.fetch('file_error'))
      .to start_with('Failed to download:')
    expect(result.fetch('export_errors').fetch('tampered_archive').fetch('raw_data_archives').first.fetch('file_error'))
      .to start_with('Failed to export archive file:')
    RSpec::Mocks.with_temporary_scope do
      allow_any_instance_of(Points::AnomalyFilter).to receive(:call).and_raise(StandardError,
                                                                               'synthetic anomaly failure')
      result['post_commit_anomaly'] = UserDataFixturesSupport.with_users do
        user = UserDataFixturesSupport.owner
        UserDataFixturesSupport.restore('post_commit_anomaly', UserDataFixturesSupport.read_entries('v2'), user)
      end
    end
    expect(result.fetch('post_commit_anomaly').fetch('result')).to include('points_created' => 3)
    expect(result.fetch('post_commit_anomaly').fetch('error')).to be_nil
    expect(result.fetch('post_commit_anomaly').fetch('notifications').last.fetch('title'))
      .to eq('Data import completed')
    RSpec::Mocks.with_temporary_scope do
      allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(StandardError, 'synthetic storage write failed')
      result['post_commit_storage_failure'] = UserDataFixturesSupport.with_users do
        UserDataFixturesSupport.restore('failed_attachment', UserDataFixturesSupport.read_entries('v2'),
                                        UserDataFixturesSupport.owner)
      end
    end
    expect(result.fetch('post_commit_storage_failure').fetch('error'))
      .to eq('class' => 'StandardError', 'message' => 'synthetic storage write failed')
    expect(result.fetch('post_commit_storage_failure').fetch('rows').fetch('points').size).to eq(3)
    expect(result.fetch('post_commit_storage_failure').fetch('notifications').map { |row| row['title'] })
      .to eq(['Synthetic <title>&', 'Data import completed', 'Data import failed'])
    UserDataFixturesSupport.write('capture.json', result)
  end

  it 'captures rescued point SQL failure aborting the outer transaction' do
    capture = UserDataFixturesSupport.with_users do
      user = UserDataFixturesSupport.owner
      result = {}
      begin
        ActiveRecord::Base.transaction do
          data = [{ 'timestamp' => 1_767_225_600, 'lonlat' => 'POINT(12.4 51.3)', 'course' => '100000000000' }]
          result['inserted'] = Users::ImportData::Points.new(user, data).call
          ActiveRecord::Base.connection.select_value('SELECT 1')
        end
      rescue ActiveRecord::StatementInvalid => e
        result['sqlstate'] = e.cause.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
      end
      result['points'] = user.points.count
      result
    end
    expect(capture).to eq('inserted' => 0, 'sqlstate' => '25P02', 'points' => 0)
    UserDataFixturesSupport.write('points_sql_failure.json', capture)
  end

  it 'portable raw payload is plaintext gzip' do
    result = UserDataFixturesSupport.portable
    bytes = Base64.strict_decode64(result.fetch('bytes'))
    expect(bytes.byteslice(0, 2).bytes).to eq([31, 139])
    expect(bytes).to eq(UserDataFixturesSupport.raw_gzip)
    expect(result.fetch('metadata')).to include('format_version' => 1,
                                                'content_checksum' => Digest::SHA256.hexdigest(bytes))
    expect(result.fetch('metadata')).not_to have_key('encryption')
    UserDataFixturesSupport.write('portable.json', result)
  end

  it 'missing manifest and data returns nil after failure notification' do
    result = UserDataFixturesSupport.failure('missing')
    expect(result.fetch('service')).to include('result' => nil, 'error' => nil)
    expect(result.fetch('service').fetch('notifications').map do |row|
      row.fetch('title')
    end).to eq(['Data import failed'])
    expect(result.fetch('job')).to include('error' => nil, 'status' => 'processing', 'points_count' => 1)
    expect(result.fetch('job').fetch('notifications').map { |row| row.fetch('title') }).to eq(['Data import failed'])
    UserDataFixturesSupport.write('missing.json', result)
  end

  it 'unsupported version raises after service and job notifications' do
    result = UserDataFixturesSupport.failure('version3')
    expected = { 'class' => 'StandardError', 'message' => 'Unsupported export format version: 3' }
    expect(result.fetch('service')).to include('result' => nil, 'error' => expected)
    expect(result.fetch('job')).to include('error' => expected, 'status' => 'failed', 'points_count' => 91)
    expect(result.fetch('service').fetch('notifications').size).to eq(1)
    expect(result.fetch('job').fetch('notifications').map { |row| row.fetch('title') })
      .to eq(['Data import failed', 'Data import failed'])
    UserDataFixturesSupport.write('version3.json', result)
  end
end
