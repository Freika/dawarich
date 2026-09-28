defmodule DawarichWeb.RequireUser do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias DawarichWeb.{RailsSession, RequestURL, Translate}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{current_user: %{}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    message = Translate.t(conn.assigns.locale, "devise.failure.unauthenticated", %{})

    changes =
      Map.put(return_to(conn), "flash", %{"discard" => [], "flashes" => %{"alert" => message}})

    conn
    |> RailsSession.stage(changes)
    |> put_resp_header("location", RequestURL.base(conn) <> "/users/sign_in")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end

  defp return_to(%{method: "GET"} = conn) do
    path = String.replace(conn.request_path, ~r/\A\/+/, "/")

    %{
      "user_return_to" =>
        if(conn.query_string == "", do: path, else: path <> "?" <> conn.query_string)
    }
  end

  defp return_to(_conn), do: %{}
end
