defmodule DawarichWeb.ApiClosureRoutes do
  @moduledoc false

  defmacro a12f2_b_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_locations_photos
        get "/photos", PhotosController, :index, metadata: %{slice: :api_locations_photos}

        get "/locations", LocationsController, :index_closure,
          metadata: %{slice: :api_locations_photos}

        get "/locations/suggestions", LocationsController, :suggestions,
          metadata: %{slice: :api_locations_photos}

        get "/photos/:id/thumbnail", PhotosController, :thumbnail_closure,
          metadata: %{slice: :api_locations_photos}

        get "/photos/:id/thumbnail.jpg", PhotosController, :thumbnail_closure,
          metadata: %{slice: :api_locations_photos}

        post "/immich/enrich/scan", ImmichController, :scan,
          metadata: %{slice: :api_locations_photos}

        post "/immich/enrich", ImmichController, :create,
          metadata: %{slice: :api_locations_photos}
      end
    end
  end
end
