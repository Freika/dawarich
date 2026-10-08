defmodule DawarichWeb do
  @moduledoc false

  def html do
    quote do
      use Phoenix.Component
      import DawarichWeb.Translate, only: [t: 3]
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView
      on_mount Dawarich.ErrorReporting.LiveViewHook
      import DawarichWeb.Translate, only: [t: 3]
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: DawarichWeb.Endpoint,
        router: DawarichWeb.Router,
        statics: ~w(native)
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
