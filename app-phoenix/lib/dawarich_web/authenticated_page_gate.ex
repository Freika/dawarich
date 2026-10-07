defmodule DawarichWeb.AuthenticatedPageGate do
  @moduledoc false
  alias DawarichWeb.{AdminWrites.Fallback, LayoutAssigns, RailsAuth}

  @pipelines ~w(rails_user rails_frame insights trial_resume user_data_export)a

  def init(opts), do: opts

  def admit?(%{pipe_through: pipelines}, conn) do
    if Dawarich.Standalone.enabled?() and conn.method in ["GET", "HEAD"] and
         Enum.any?(pipelines, &(&1 in @pipelines)) do
      user = RailsAuth.call(conn, []).assigns.current_user
      is_nil(user) or (:admin_page in pipelines and refused?(user))
    else
      false
    end
  end

  def admit?(_route, _conn), do: false

  def call(conn, _opts) do
    if Dawarich.Standalone.enabled?() and refused?(conn.assigns.current_user),
      do: Fallback.call(conn, action: :page),
      else: conn
  end

  defp refused?(user), do: not LayoutAssigns.self_hosted?() or user.admin != true
end
