# frozen_string_literal: true

module Achievements
  class GeographicResults
    PARK_THRESHOLDS = [1, 5, 15].freeze

    def self.call(dataset, observed)
      milestones = GeographicRegions::GROUPS.map do |key, members|
        regions = members.map do |member|
          (observed[member] || { 'seconds' => 0,
'target' => ObservedTime::GEOGRAPHIC_TARGET }).merge('region' => member)
        end
        evidence = members.filter_map do |member|
          fact = observed[member]
          fact.merge('region' => member) if fact && fact['seconds'] >= ObservedTime::GEOGRAPHIC_TARGET
        end
        complete = evidence.size == members.size
        { series: 'milestone', subject_key: key, selection_id: nil,
          data: { 'name' => key, 'progress' => evidence.size, 'target' => members.size,
                  'timezone' => evidence.max_by { |row| row['at'] }&.fetch('timezone') || 'UTC',
                  'levels' => complete ? { '1' => evidence.map { |row| row['at'] }.max } : {},
                  'evidence' => evidence, 'regions' => regions, 'status' => 'ready' } }
      end
      parks = if dataset
                Exploration::Territory.where(dataset_id: dataset.id, kind: 'park').filter_map do |park|
                  fact = observed[park.code]
                  next unless fact

                  { series: 'park', subject_key: park.code, selection_id: nil,
                    data: { 'name' => park.name, 'progress' => fact['seconds'], 'target' => ObservedTime::PARK_TARGET,
                            'timezone' => park.timezone, 'territory_id' => park.id, 'territory_code' => park.code,
                            'source' => park.source_metadata, 'dataset_id' => dataset.id, 'status' => 'ready',
                            'levels' => fact['seconds'] >= ObservedTime::PARK_TARGET ? { '1' => fact['at'] } : {},
                            'evidence' => [fact.merge('region' => park.code)] } }
                end
              else
                []
              end
      completed = parks.select { |park| park[:data]['levels'].any? }.sort_by { |park| park[:data]['levels']['1'] }
      levels = PARK_THRESHOLDS.each_with_index.filter_map do |threshold, index|
        [(index + 1).to_s, completed[threshold - 1][:data]['levels']['1']] if completed.size >= threshold
      end.to_h
      attained = PARK_THRESHOLDS.select { |threshold| threshold <= completed.size }.last
      earned_zone = attained ? completed[attained - 1].dig(:data, 'timezone') : 'UTC'
      counter = { series: 'parks', subject_key: 'national_parks', selection_id: nil,
                  data: { 'name' => 'national_parks', 'progress' => completed.size,
                          'target' => PARK_THRESHOLDS.find do |threshold|
                            threshold > completed.size
                          end || PARK_THRESHOLDS.last,
                          'levels' => levels, 'timezone' => earned_zone,
                          'status' => dataset ? 'ready' : 'catalog_required',
                          'catalog_count' => if dataset
                                               Exploration::Territory.where(dataset_id: dataset.id, kind: 'park').count
                                             else
                                               0
                                             end,
                          'evidence' => completed.map do |park|
                            park[:data]['evidence'].first.merge('name' => park[:data]['name'])
                          end } }
      milestones + parks + [counter]
    end
  end
end
