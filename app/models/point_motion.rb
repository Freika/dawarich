# frozen_string_literal: true

class PointMotion < ApplicationRecord
  def self.digest_sql(table_alias)
    "md5(#{table_alias}.motion_data::text)"
  end
end
