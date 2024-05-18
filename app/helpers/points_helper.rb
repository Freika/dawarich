# frozen_string_literal: true

module PointsHelper
  def link_to_date(timestamp)
    datetime = Time.zone.at(timestamp)

    link_to points_path(start_at: datetime.beginning_of_day, end_at: datetime.end_of_day), \
            class: 'underline hover:no-underline' do
      datetime.strftime('%d.%m.%Y')
    end
  end
end
