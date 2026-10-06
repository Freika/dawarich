defmodule DawarichWeb.ApiWriteRoutes do
  @moduledoc false

  defmacro a12f2_e_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_stats
        get "/imports", ImportsController, :index, metadata: %{slice: :ingest}
        get "/imports/:id", ImportsController, :show, metadata: %{slice: :ingest}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_pending
        post "/imports/pending", PendingImportsController, :create, metadata: %{slice: :ingest}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_ingest
        post "/imports", ImportsController, :create, metadata: %{slice: :ingest}

        delete "/points/bulk_destroy", PointWritesController, :bulk_destroy,
          metadata: %{slice: :ingest}

        post "/points/reapply_anomaly_filter", AnomalyController, :create,
          metadata: %{slice: :ingest}

        patch "/points/:point_id/position", PointPositionsController, :update,
          metadata: %{slice: :ingest}

        put "/points/:point_id/position", PointPositionsController, :update,
          metadata: %{slice: :ingest}

        patch "/points/:id", PointWritesController, :update, metadata: %{slice: :ingest}
        put "/points/:id", PointWritesController, :update, metadata: %{slice: :ingest}
        delete "/points/:id", PointWritesController, :destroy, metadata: %{slice: :ingest}
      end
    end
  end
end
