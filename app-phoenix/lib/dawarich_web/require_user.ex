defmodule DawarichWeb.RequireUser do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias DawarichWeb.{RailsSession, RequestURL, Translate}

  @logout %{"warden.user.user.key" => nil, "warden.user.user.session" => nil}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{request_path: "/admin/settings", assigns: %{current_user: %{} = user}} = conn, _opts) do
    if Dawarich.Standalone.enabled?() and
         (System.get_env("SELF_HOSTED") != "true" or user.admin != true) do
      DawarichWeb.AdminWrites.Fallback.call(conn, action: :instance)
    else
      conn
    end
  end

  def call(%{assigns: %{current_user: %{}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn =
      if Dawarich.Standalone.enabled?() and conn.request_path in ~w(/trial/upgrade /trial/resume),
        do: DawarichWeb.TrialHomeSession.call(conn, []),
        else: conn

    locked = conn.assigns[:rails_locked]
    reason = if locked, do: "devise.failure.locked", else: "devise.failure.unauthenticated"
    message = Translate.t(conn.assigns.locale, reason, %{})

    changes = %{
      "user_return_to" => return_to(conn),
      "flash" => %{"discard" => [], "flashes" => %{"alert" => message}}
    }

    if DawarichWeb.PageEnvelope.xhr?(conn) do
      DawarichWeb.PageEnvelope.unauthorized(conn, message)
    else
      conn
      |> RailsSession.stage(if locked == :session, do: Map.merge(changes, @logout), else: changes)
      |> put_resp_header("location", RequestURL.base(conn) <> "/users/sign_in")
      |> put_resp_content_type("text/html")
      |> send_resp(302, "")
      |> halt()
    end
  end

  defp return_to(conn) do
    {original_path, original_query} = DawarichWeb.PageEnvelope.original_target(conn)
    path = String.replace(original_path, ~r/\A\/+/, "/")
    if original_query == "", do: path, else: path <> "?" <> original_query
  end
end
