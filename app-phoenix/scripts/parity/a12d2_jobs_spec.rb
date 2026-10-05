# frozen_string_literal: true

require 'rails_helper'
require_relative 'a12d2_jobs_support'
require_relative 'a12d2_release_support'

RSpec.describe 'Phoenix fixture: A12d2 residual jobs' do
  include ActiveSupport::Testing::TimeHelpers
  include A12d2JobsSupport
  include A12d2ReleaseSupport
  self.use_transactional_tests = false

  let(:path) { Rails.root.join('app-phoenix/test/fixtures/a12d2/jobs.json') }
  let(:source_classes) do
    %w[Tracks::BackfillGenerationJob Tracks::ThrottledBackfillJob AirTrail::SyncSchedulingJob
       TeslaMate::SyncSchedulingJob Trek::SyncSchedulingJob Families::AutoCreationJob
       Families::MemberSyncJob Places::NameFetchingJob Places::BulkNameFetchingJob
       Places::DeleteIfOrphanJob Places::OrphanCleanupJob Achievements::BulkCheckJob]
  end

  it 'A12rel achievements parent records guard load ordering and failures' do
    corpus = capture_release_achievements
    cases = corpus.fetch('cases').index_by { _1.fetch('id') }
    expect(corpus.fetch('retry').fetch('max_attempts')).to eq(26)
    expect(cases.fetch('countries_empty')).to include('jobs' => [], 'statements' => [], 'error' => nil)
    %w[required_present cloud self_hosted legacy_disabled repeat].each do |name|
      row = cases.fetch(name)
      expect(row.fetch('error')).to be_nil
      expect(row.fetch('jobs').size).to eq(name == 'repeat' ? 2 : 1)
      row.fetch('jobs').each do |job|
        expect(job).to include('class' => 'Achievements::BulkCheckJob', 'due_offset' => 0,
                               'arguments' => [{ 'notify' => false, 'force' => true, 'stale_only' => true }])
      end
    end
    expect(cases.fetch('equal_count_missing').fetch('before').size).to eq(corpus.fetch('required_codes').size)
    expect(cases.fetch('equal_count_missing').fetch('statements').map { _1.fetch('kind') })
      .to eq(%w[upsert repair])
    %w[load_failure enqueue_failure repair_failure].each do |name|
      expect(cases.fetch(name).fetch('error')).not_to be_nil
      expect(cases.fetch(name).fetch('jobs')).to eq([])
    end
    %w[enqueue_failure repair_failure].each do |name|
      row = cases.fetch(name)
      expect(row.fetch('observed')).to eq(row.fetch('after'))
      expect(row.fetch('retry').fetch('jobs').size).to eq(1)
      expect(row.fetch('retry').fetch('statements')).to eq([])
    end
    expect(cases.fetch('repair_failure').fetch('after').any? { !_1.fetch('valid') }).to be(true)
    expect(capture_release_achievements).to eq(corpus)
    record_release_fixture('achievements', corpus)
  end

  it 'A12rel achievement migrations record no-argument immediate jobs' do
    corpus = capture_release_achievement_vectors
    expect(corpus.fetch('vectors').map { _1.fetch('version') }).to eq(%w[20260922120000 20260923180000])
    corpus.fetch('vectors').each do |row|
      expected = { 'class' => 'DataMigrations::BackfillAchievementsJob', 'queue' => 'data_migrations',
                   'arguments' => [], 'due_offset' => 0 }
      expect(row.fetch('jobs')).to eq([expected])
    end
    expect(capture_release_achievement_vectors).to eq(corpus)
    record_release_fixture('release_vectors', corpus)
  end

  it 'captures residual jobs with fixed ids clocks and source outcomes' do
    corpus = capture_jobs
    expect(corpus.fetch('classes').keys).to match_array(source_classes)
    corpus.fetch('classes').each do |name, entry|
      expect(entry.keys).to include('retry', 'cases')
      expect(entry.fetch('cases').map { _1.fetch('id') }).to include('repeat', 'scope', 'error')
      expect(entry.fetch('cases').map { _1.fetch('id') }).to eq(A12d2JobsSupport::CASES.fetch(name))
    end
    boundary = corpus.fetch('classes').fetch('Tracks::BackfillGenerationJob').fetch('cases')
                     .find { _1.fetch('id') == 'lookback_boundary' }
    expect(boundary).to include('jobs' => [], 'range' => nil)
    corpus.fetch('classes').each do |name, entry|
      failure = entry.fetch('cases').find { _1.fetch('id') == 'error' }
      if %w[Tracks::BackfillGenerationJob Places::NameFetchingJob].include?(name)
        expect(failure.fetch('error')).to be_nil
        expect(failure.fetch('reported')).not_to be_empty
      else
        expect(failure.fetch('error')).to include('class' => 'RuntimeError')
      end
    end
    walk = corpus.fetch('classes').fetch('Tracks::ThrottledBackfillJob').fetch('cases')
    expect(walk.find { _1.fetch('id') == 'active_ttl' }.fetch('ttl')).to eq(43_200)
    expect(walk.find { _1.fetch('id') == 'backoff_ttl' }.fetch('ttl')).to eq(604_800)
    achievements = corpus.fetch('classes').fetch('Achievements::BulkCheckJob').fetch('cases')
    batch = achievements.find { _1.fetch('id') == 'batches' }.fetch('jobs')
    expect(batch.map { _1.fetch('due_offset') }.uniq).to eq([0, 300, 600])
    serialized = "#{JSON.pretty_generate(corpus)}\n"
    second = capture_jobs
    corpus.fetch('classes').each do |name, entry|
      entry.fetch('cases').each_with_index do |row, index|
        expect(second.fetch('classes').fetch(name).fetch('cases').fetch(index) == row)
          .to be(true), "#{name}/#{row.fetch('id')} differs between captures"
      end
    end
    expect("#{JSON.pretty_generate(second)}\n" == serialized).to be(true)
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(path.dirname)
      File.write(path, serialized)
    else
      expect(serialized).to eq(path.read)
    end
  end

  it 'source single orphan deletion detaches an active visit added after eligibility' do
    expect(capture_orphan_race(:single)).to include(
      'result' => true, 'place_exists' => false, 'active_visit_place_id' => nil
    )
  end

  it 'captures A12d3 schedule parents twice with fixed source outcomes' do
    corpus = capture_schedule_parents
    nightly = corpus.fetch('classes').fetch('Points::NightlyReverseGeocodingJob').fetch('cases')
    forced = nightly.find { _1.fetch('id') == 'dedup' }
    expect(forced.fetch('jobs')).to eq([])
    expect(capture_schedule_parents).to eq(corpus)
    serialized = "#{JSON.pretty_generate(corpus)}\n"
    schedules_path = Rails.root.join('app-phoenix/test/fixtures/a12d3/schedules.json')
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(schedules_path.dirname)
      File.write(schedules_path, serialized)
    else
      expect(serialized).to eq(schedules_path.read)
    end
  end

  it 'captures family sync failures after the source transaction rolls back' do
    %w[sync_error error].each do |profile|
      captured = source_isolated('Families::AutoCreationJob', profile) do
        source_case('Families::AutoCreationJob', profile)
      end
      expect(captured.fetch('error')).to include('message' => 'fixture sync failure')
      expect(captured.fetch('families')).to eq([])
      expect(captured.fetch('memberships')).to eq([])
      expect(captured.fetch('settings')).not_to have_key('family')
    end
    %w[member_error error].each do |profile|
      captured = source_isolated('Families::MemberSyncJob', profile) do
        source_case('Families::MemberSyncJob', profile)
      end
      expect(captured.fetch('error')).to include('class' => 'RuntimeError')
      member = captured.fetch('members').find { _1.fetch('id') == A12d2JobsSupport::OTHER_ID }
      expect(member).to include('plan' => 'lite', 'status' => 'inactive',
                                'active_until' => '2026-10-03T14:00:00.000000+02:00')
      expect(member.fetch('settings')).not_to have_key('family')
    end
  end

  it 'source orphan sweep detaches an active visit added after victim selection' do
    expect(capture_orphan_race(:sweep)).to include(
      'deleted_count' => 1, 'place_exists' => false, 'active_visit_place_id' => nil
    )
  end
end
