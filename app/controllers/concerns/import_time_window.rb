# frozen_string_literal: true

module ImportTimeWindow
  extend ActiveSupport::Concern

  private

  def import_window_start
    return @import_window_start if defined?(@import_window_start)

    load_import_window!
    @import_window_start
  end

  def import_window_end
    return @import_window_end if defined?(@import_window_end)

    load_import_window!
    @import_window_end
  end

  def import_record
    return @import_record if defined?(@import_record)

    @import_record = params[:import_id].present? ? current_user.imports.find_by(id: params[:import_id]) : nil
  end

  def load_import_window!
    min_ts, max_ts = import_record&.points&.pick(Arel.sql('MIN(timestamp)'), Arel.sql('MAX(timestamp)'))

    @import_window_start = min_ts ? Time.zone.at(min_ts).beginning_of_day.to_i : nil
    @import_window_end   = max_ts ? Time.zone.at(max_ts).end_of_day.to_i : nil
  end
end
