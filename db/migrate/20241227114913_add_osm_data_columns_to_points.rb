# frozen_string_literal: true

class AddOsmDataColumnsToPoints < ActiveRecord::Migration[8.0]
  def change
    add_column :points, :osm_id,        :string
    add_column :points, :osm_type,      :string
    add_column :points, :osm_key,       :string
    add_column :points, :osm_value,     :string
    add_column :points, :osm_district,  :string

    add_column :points, :post_code,       :string
    add_column :points, :type,            :string
    add_column :points, :house_number,    :string
    add_column :points, :street,          :string
    add_column :points, :name,            :string
    add_column :points, :district,        :string
    add_column :points, :locality,        :string
    add_column :points, :importance,      :string
    add_column :points, :object_type,     :string
    add_column :points, :classification,  :string
  end
end
