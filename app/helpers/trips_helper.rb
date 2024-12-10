# frozen_string_literal: true

module TripsHelper
  def immich_search_url(base_url, start_date, end_date)
    query = {
      takenAfter: "#{start_date.to_date}T00:00:00.000Z",
      takenBefore: "#{end_date.to_date}T23:59:59.999Z"
    }

    encoded_query = URI.encode_www_form_component(query.to_json)
    "#{base_url}/search?query=#{encoded_query}"
  end

  def photoprism_search_url(base_url, start_date, _end_date)
    "#{base_url}/library/browse?view=cards&year=#{start_date.year}&month=#{start_date.month}&order=newest&public=true&quality=3"
  end

  def photo_search_url(source, settings, start_date, end_date)
    case source
    when 'immich'
      immich_search_url(settings['immich_url'], start_date, end_date)
    when 'photoprism'
      photoprism_search_url(settings['photoprism_url'], start_date, end_date)
    end
  end
end
