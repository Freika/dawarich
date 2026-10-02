defmodule DawarichWeb.InsightsGate do
  @moduledoc "Admission for the Insights details GET and authenticated home redirect."
  alias Dawarich.{Accounts, Auth.Admission}
  alias DawarichWeb.RailsAuth
  import Plug.Conn

  def owned?(conn) do
    conn = RailsAuth.call(conn, [])
    user = conn.assigns.current_user
    session = conn.assigns.rails_session
    ordinary = Accounts.from_session(session, DateTime.utc_now())
    remembered = is_nil(ordinary)

    user != nil and conn.assigns.rails_locked == nil and page_request?(conn) and
      Admission.headers(conn.req_headers) == :ok and
      (not remembered or
         Admission.context(
           session,
           conn.req_headers,
           false,
           System.get_env("SELF_HOSTED") == "true"
         ) == :ok)
  end

  def page_request?(conn) do
    accept = conn |> get_req_header("accept") |> Enum.join(",")

    types =
      accept
      |> String.split(",")
      |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim() |> String.downcase()))

    params = Plug.Conn.Query.decode(conn.query_string)

    conn.method in ["GET", "HEAD"] and not Map.has_key?(params, "format") and
      not Enum.any?(
        get_req_header(conn, "x-requested-with"),
        &String.match?(&1, ~r/XMLHttpRequest/i)
      ) and
      (types == [""] or DawarichWeb.Strangler.browser_like?(accept) or
         (Enum.all?(
            types,
            &(&1 in ["text/html", "*/*", "application/xhtml+xml", "text/vnd.turbo-stream.html"])
          ) and
            Enum.any?(types, &(&1 in ["text/html", "*/*"]))))
  end
end
