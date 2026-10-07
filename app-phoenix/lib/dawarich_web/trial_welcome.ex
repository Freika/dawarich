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
      conn =
        if Dawarich.Standalone.enabled?() do
          conn
          |> DawarichWeb.RailsAuth.call(
            secret: context.secret,
            now: (context[:clock] && context.clock.()) || DateTime.utc_now()
          )
          |> fetch_query_params()
          |> DawarichWeb.Locale.call([])
          |> DawarichWeb.TrialHomeSession.call([])
        else
          conn
        end

      case Welcome.prepare(conn, Plug.Conn.Query.decode(conn.query_string), context) do
        {:ok, prepared} ->
          case Welcome.consume(prepared, context) do
            {:ok, result} -> respond(conn, result)
            {:terminal, _} -> terminal(conn)
          end

        {:handoff, _} ->
          proxy(conn)
      end
    else
      proxy(conn)
    end
  end

  defp respond(conn, result) do
    redirect(conn, result)
  rescue
    _ -> terminal(conn)
  end

  defp terminal(conn), do: conn |> headers() |> send_resp(500, "") |> halt()

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

  defp proxy(conn) do
    if Dawarich.Standalone.enabled?(),
      do: conn |> headers() |> DawarichWeb.StandaloneError.respond("welcome_envelope", 422),
      else: RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
  end
end
