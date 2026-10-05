# frozen_string_literal: true

require 'rails_helper'
require_relative 'a12d2_jobs_support'

RSpec.describe 'Phoenix fixture: A12d2 residual jobs' do
  include ActiveSupport::Testing::TimeHelpers
  include A12d2JobsSupport
  self.use_transactional_tests = false

  let(:path) { Rails.root.join('app-phoenix/test/fixtures/a12d2/jobs.json') }
  let(:source_classes) do
    %w[Tracks::BackfillGenerationJob Tracks::ThrottledBackfillJob AirTrail::SyncSchedulingJob
       TeslaMate::SyncSchedulingJob Trek::SyncSchedulingJob Families::AutoCreationJob
       Families::MemberSyncJob Places::NameFetchingJob Places::BulkNameFetchingJob
       Places::DeleteIfOrphanJob Places::OrphanCleanupJob Achievements::BulkCheckJob]
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
