defmodule DawarichWeb.ApiWriteRoutes do
  @moduledoc false

  defmacro a12f2_e_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_stats
        get "/imports", ImportsController, :index, metadata: %{slice: :ingest, native_api: true}

        get "/imports/:id", ImportsController, :show,
          metadata: %{slice: :ingest, native_api: true}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_pending

        post "/imports/pending", PendingImportsController, :create,
          metadata: %{slice: :ingest, native_api: true}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_ingest
        post "/imports", ImportsController, :create, metadata: %{slice: :ingest, native_api: true}

        delete "/points/bulk_destroy", PointWritesController, :bulk_destroy,
          metadata: %{slice: :ingest, native_api: true}

        post "/points/reapply_anomaly_filter", AnomalyController, :create,
          metadata: %{slice: :ingest, native_api: true}

        patch "/points/:point_id/position", PointPositionsController, :update,
          metadata: %{slice: :ingest, native_api: true}

        put "/points/:point_id/position", PointPositionsController, :update,
          metadata: %{slice: :ingest, native_api: true}

        patch "/points/:id", PointWritesController, :update,
          metadata: %{slice: :ingest, native_api: true}

        put "/points/:id", PointWritesController, :update,
          metadata: %{slice: :ingest, native_api: true}

        delete "/points/:id", PointWritesController, :destroy,
          metadata: %{slice: :ingest, native_api: true}
      end
    end
  end
end
