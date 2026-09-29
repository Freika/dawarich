defmodule DawarichWeb.RequireUser do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias DawarichWeb.{RailsSession, RequestURL, Translate}

  @logout %{"warden.user.user.key" => nil, "warden.user.user.session" => nil}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{current_user: %{}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    locked = conn.assigns[:rails_locked]
    reason = if locked, do: "devise.failure.locked", else: "devise.failure.unauthenticated"
    message = Translate.t(conn.assigns.locale, reason, %{})

    changes = %{
      "user_return_to" => return_to(conn),
      "flash" => %{"discard" => [], "flashes" => %{"alert" => message}}
    }

    conn
    |> RailsSession.stage(if locked == :session, do: Map.merge(changes, @logout), else: changes)
    |> put_resp_header("location", RequestURL.base(conn) <> "/users/sign_in")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end

  defp return_to(conn) do
    path = String.replace(conn.request_path, ~r/\A\/+/, "/")
    if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string
  end
end
