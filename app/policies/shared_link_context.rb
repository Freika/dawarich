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
    settings['show_photos'] == true
  end

  def show_stats?
    settings['show_stats'] == true
  end

  def show_day_notes?
    settings['show_day_notes'] == true
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
