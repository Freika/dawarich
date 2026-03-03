# frozen_string_literal: true

module FlashHelper
  def flash_alert_class(type)
    case type.to_sym
    when :notice, :success then 'alert-success'
    when :alert, :error then 'alert-error'
    when :warning then 'alert-warning'
    else 'alert-info'
    end
  end

  def flash_icon(type)
    case type.to_sym
    when :notice, :success then icon 'circle-check'
    when :alert, :error then icon 'circle-x'
    when :warning then icon 'circle-alert'
    else
      icon 'info'
    end
  end
end
