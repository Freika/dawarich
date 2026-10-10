# frozen_string_literal: true

module SchemaParity
  module GitTags
    module_function

    def files_by_release
      ReleaseMap.release_tags(`git tag -l`.split).map { |tag| [tag, files_at(tag)] }
    end

    def files_at(tag)
      raise ArgumentError, "not a release tag: #{tag}" unless tag.match?(ReleaseMap::RELEASE_TAG)

      `git ls-tree -r --name-only refs/tags/#{tag} -- db/migrate db/data`.split
    end
  end
end
