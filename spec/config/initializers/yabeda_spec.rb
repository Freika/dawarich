# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Yabeda metrics registration' do
  describe 'dawarich_archive group' do
    it 'is defined' do
      expect(Yabeda.groups[:dawarich_archive]).not_to be_nil
    end

    it 'declares operations_total counter with operation + status tags' do
      metric = Yabeda.metrics['dawarich_archive_operations_total']
      expect(metric).to be_a(Yabeda::Counter)
      expect(metric.tags).to match_array(%i[operation status])
    end

    it 'declares points_total counter with operation tag' do
      metric = Yabeda.metrics['dawarich_archive_points_total']
      expect(metric).to be_a(Yabeda::Counter)
      expect(metric.tags).to eq(%i[operation])
    end

    it 'declares compression_ratio histogram with 0.1..1.0 buckets' do
      metric = Yabeda.metrics['dawarich_archive_compression_ratio']
      expect(metric).to be_a(Yabeda::Histogram)
      expect(metric.buckets).to eq([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
    end

    it 'declares count_mismatches_total counter with year + month tags' do
      metric = Yabeda.metrics['dawarich_archive_count_mismatches_total']
      expect(metric).to be_a(Yabeda::Counter)
      expect(metric.tags).to match_array(%i[year month])
    end

    it 'declares count_difference gauge with user_id tag' do
      metric = Yabeda.metrics['dawarich_archive_count_difference']
      expect(metric).to be_a(Yabeda::Gauge)
      expect(metric.tags).to eq(%i[user_id])
    end

    it 'declares size_bytes histogram with size buckets' do
      metric = Yabeda.metrics['dawarich_archive_size_bytes']
      expect(metric).to be_a(Yabeda::Histogram)
      expect(metric.buckets).to eq([1_000_000, 10_000_000, 50_000_000, 100_000_000, 500_000_000, 1_000_000_000])
    end

    it 'declares verification_duration_seconds histogram with status tag' do
      metric = Yabeda.metrics['dawarich_archive_verification_duration_seconds']
      expect(metric).to be_a(Yabeda::Histogram)
      expect(metric.tags).to eq(%i[status])
      expect(metric.buckets).to eq([0.1, 0.5, 1, 2, 5, 10, 30, 60])
    end

    it 'declares verification_failures_total counter with check tag' do
      metric = Yabeda.metrics['dawarich_archive_verification_failures_total']
      expect(metric).to be_a(Yabeda::Counter)
      expect(metric.tags).to eq(%i[check])
    end
  end

  describe 'dawarich_map group' do
    it 'declares low-cardinality move, publication, and tile metrics' do
      expect(Yabeda.groups[:dawarich_map]).not_to be_nil
      expect(Yabeda.metrics['dawarich_map_point_moves_total']).to be_a(Yabeda::Counter)
      expect(Yabeda.metrics['dawarich_map_point_move_duration_seconds']).to be_a(Yabeda::Histogram)
      expect(Yabeda.metrics['dawarich_map_point_move_lock_wait_seconds']).to be_a(Yabeda::Histogram)
      expect(Yabeda.metrics['dawarich_map_point_move_track_points']).to be_a(Yabeda::Histogram)
      expect(Yabeda.metrics['dawarich_map_point_move_track_segments']).to be_a(Yabeda::Histogram)
      expect(Yabeda.metrics['dawarich_map_post_commit_failures_total']).to be_a(Yabeda::Counter)
      expect(Yabeda.metrics['dawarich_map_tile_requests_total']).to be_a(Yabeda::Counter)
      expect(Yabeda.metrics['dawarich_map_tile_request_duration_seconds']).to be_a(Yabeda::Histogram)
    end

    it 'uses only bounded outcome, operation, and layer labels' do
      expect(Yabeda.dawarich_map.point_moves_total.tags).to eq(%i[outcome])
      expect(Yabeda.dawarich_map.post_commit_failures_total.tags).to eq(%i[operation])
      expect(Yabeda.dawarich_map.tile_requests_total.tags).to eq(%i[layer outcome])
    end
  end
end
