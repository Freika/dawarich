# frozen_string_literal: true

module SchemaParity
  class ReleaseMap
    RELEASE_TAG = /\A\d+(\.\d+){2,3}\z/
    VERSION_PREFIX = /\A(\d+)_/

    def self.release_tags(tags)
      tags.grep(RELEASE_TAG).sort_by { |tag| Gem::Version.new(tag) }
    end

    def self.versions(paths, directory)
      paths.filter_map { |path| path.start_with?("#{directory}/") && File.basename(path)[VERSION_PREFIX, 1] }.sort
    end

    def self.missing_releases(committed_states, states)
      committed_states.flat_map { _1['releases'] } - states.flat_map { _1[:releases] }
    end

    def initialize(files_by_tag)
      @files_by_tag = files_by_tag
    end

    def states
      previous = { schema: [], data: [] }

      @files_by_tag.each_with_object([]) do |(tag, paths), states|
        current = { schema: self.class.versions(paths, 'db/migrate'), data: self.class.versions(paths, 'db/data') }

        if states.any? && current == previous
          states.last[:releases] << tag
        else
          states << state(tag, previous, current)
        end

        previous = current
      end
    end

    private

    def state(tag, previous, current)
      {
        first_release: tag,
        releases: [tag],
        schema_added: current[:schema] - previous[:schema],
        schema_removed: previous[:schema] - current[:schema],
        data_added: current[:data] - previous[:data],
        data_removed: previous[:data] - current[:data]
      }
    end
  end
end
