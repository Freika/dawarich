defmodule DawarichWeb.TrialWelcome do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Trial.Welcome
  alias DawarichWeb.{AuthCookie, RailsHeaders, RailsProxy, RequestURL, WelcomeGate}
  def init(opts), do: opts
  def call(%{halted: true} = conn, _opts), do: conn

  def call(conn, opts) do
    context = WelcomeGate.context(opts)

    if WelcomeGate.envelope?(conn) do
      case Welcome.prepare(conn, URI.decode_query(conn.query_string), context) do
        {:ok, prepared} ->
          case Welcome.consume(prepared, context) do
            {:ok, result} -> redirect(conn, result)
            {:terminal, _} -> conn |> headers() |> send_resp(500, "") |> halt()
          end

        {:handoff, _} ->
          proxy(conn)
      end
    else
      proxy(conn)
    end
  end

  defp redirect(conn, result) do
    conn = if result.cookie, do: AuthCookie.session(conn, result.cookie), else: conn

    conn
    |> headers()
    |> put_resp_content_type("text/html")
    |> put_resp_header("location", RequestURL.base(conn) <> result.path)
    |> put_resp_header("x-dawarich-trial-owner", "native-welcome")
    |> send_resp(302, "")
    |> halt()
  end

  defp headers(conn) do
    conn
    |> RailsHeaders.call([])
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("referrer-policy", "no-referrer")
  end

  defp proxy(conn), do: RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
end
