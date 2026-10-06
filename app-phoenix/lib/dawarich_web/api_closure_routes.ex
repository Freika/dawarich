defmodule DawarichWeb.ApiClosureRoutes do
  @moduledoc false

  def deferred?(conn) do
    case conn.path_info do
      ["api", "v1", area | _]
      when area in ~w(auth areas settings demo_data recalculations subscriptions) ->
        true

      ["api", "v1", "users", "me"] ->
        conn.method == "DELETE"

      ["api", "v1", "digests" | _] ->
        conn.method not in ~w(GET HEAD)

      _ ->
        false
    end
  end

  defmacro a12f2_b_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_locations_photos

        get "/photos", PhotosController, :index,
          metadata: %{slice: :api_locations_photos, native_api: true}

        get "/locations", LocationsController, :index_closure,
          metadata: %{slice: :api_locations_photos}

        get "/locations/suggestions", LocationsController, :suggestions,
          metadata: %{slice: :api_locations_photos, native_api: true}

        get "/photos/:id/thumbnail", PhotosController, :thumbnail_closure,
          metadata: %{slice: :api_locations_photos}

        get "/photos/:id/thumbnail.jpg", PhotosController, :thumbnail_closure,
          metadata: %{slice: :api_locations_photos}

        post "/immich/enrich/scan", ImmichController, :scan,
          metadata: %{slice: :api_locations_photos, native_api: true}

        post "/immich/enrich", ImmichController, :create,
          metadata: %{slice: :api_locations_photos, native_api: true}
      end
    end
  end
end
