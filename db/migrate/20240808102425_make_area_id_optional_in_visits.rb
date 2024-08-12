# frozen_string_literal: true

class MakeAreaIdOptionalInVisits < ActiveRecord::Migration[7.1]
  def change
    change_column_null :visits, :area_id, true
  end
end
