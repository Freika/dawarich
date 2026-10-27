# frozen_string_literal: true

module Places
  class BulkAction
    class InvalidSelection < StandardError; end

    def initialize(user:, place_ids:)
      @user = user
      @place_ids = Array(place_ids).compact_blank.uniq
    end

    def call(operation:, tag_id: nil, survivor_id: nil)
      Place.transaction do
        places = user.places.where(id: place_ids).order(:id).lock.to_a
        raise InvalidSelection if places.empty?

        case operation
        when 'add_tag', 'remove_tag'
          tag = user.tags.find_by(id: tag_id)
          raise InvalidSelection unless tag

          places.each do |place|
            if operation == 'add_tag'
              place.tags << tag unless place.tags.exists?(tag.id)
              place.adopt!
              tag.adopt!
            else
              place.tags.destroy(tag)
            end
          end
        when 'archive', 'unarchive'
          places.each { |place| place.update!(archived: operation == 'archive') }
        when 'delete'
          places.each { |place| Destroy.new(user:, place:).call }
        when 'merge'
          survivor = places.find { |place| place.id.to_s == survivor_id.to_s }
          raise InvalidSelection unless survivor && places.size > 1

          places.reject { |place| place.id == survivor.id }.each do |duplicate|
            Merge.new(user:, survivor:, duplicate:).call
          end
        else
          raise InvalidSelection
        end
        places.size
      end
    end

    private

    attr_reader :user, :place_ids
  end
end
