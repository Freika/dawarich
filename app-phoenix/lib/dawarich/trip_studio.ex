defmodule Dawarich.TripStudio do
  @moduledoc false
  alias Dawarich.{MapGallery, MapPage, RailsMessages}

  def load(user_id, zone) do
    %{
      themes: MapPage.poster_themes(),
      posters: MapGallery.posters(user_id),
      route_videos: MapGallery.route_videos(user_id, zone),
      posters_stream: RailsMessages.stream_name([{:user, user_id}, "posters"]),
      print_order_url: System.get_env("PRINT_ORDER_URL", "https://prints.dawarich.app/api/orders")
    }
  end
end
