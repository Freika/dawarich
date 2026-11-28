# frozen_string_literal: true

class SharedLinkContext
  attr_reader :shared_link

  def initialize(shared_link)
    @shared_link = shared_link
  end

  def owner
    shared_link.user
  end

  def settings
    shared_link.settings || {}
  end

  def show_photos?
    # External photo libraries cannot be attributed to an individual import.
    settings['show_photos'] == true && !shared_link.timeline_import_scoped?
  end

  def show_stats?
    settings['show_stats'] == true
  end

  def show_day_notes?
    settings['show_day_notes'] == true
  end

  # Map notes are shown for a period of time, so only on the links that share
  # one. A note belongs to no import, so an import-scoped link shows none.
  def show_map_notes?
    settings['show_map_notes'] == true && (shared_link.timeline? || shared_link.track?) &&
      !shared_link.timeline_import_scoped?
  end

  def show_route?
    settings['show_route'] != false
  end

  def show_countries?
    settings['show_countries'] != false
  end

  def show_description?
    settings['show_description'] != false
  end

  def show_days?
    settings['show_days'] != false
  end
end
