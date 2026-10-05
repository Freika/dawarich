defmodule DawarichWeb.ImportRoutes do
  @moduledoc false
  defmacro import_routes do
    quote do
      scope "/" do
        pipe_through :imports_request
        post "/imports", DawarichWeb.ImportsController, :create
        post "/imports/:id", DawarichWeb.ImportsController, :update, metadata: @native_import
        patch "/imports/:id", DawarichWeb.ImportsController, :update, metadata: @native_import
        delete "/imports/:id", DawarichWeb.ImportsController, :delete, metadata: @native_import

        post "/imports/:id/extraction", DawarichWeb.ImportsController, :extract,
          metadata: @native_import

        delete "/imports/:id/extraction", DawarichWeb.ImportsController, :remove_extraction,
          metadata: @native_import
      end
    end
  end
end
