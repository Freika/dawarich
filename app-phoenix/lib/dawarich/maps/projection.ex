defmodule Dawarich.Maps.Projection do
  @moduledoc false

  @fields ~w(window import_id plan full_access place tags timeline_tags themes live_share demo_data print_order_url family features_json live_map airtrail fog_mode hidden_tile_categories disabled_poi_groups transport_modes immich timezone)a

  def page(page), do: Map.take(page, @fields)
end
