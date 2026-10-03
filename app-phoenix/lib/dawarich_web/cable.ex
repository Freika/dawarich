defmodule DawarichWeb.Cable do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Dawarich.Cable.Identity
  alias Dawarich.RailsSecret
  alias DawarichWeb.{CableProxy, LayoutAssigns, RackScheme, RailsAuth, SharedLinkCookie}

  @protocols ["actioncable-v1-json", "actioncable-unsupported"]
  @localhost ~r/https?:\/\/localhost:\d+/
  @bad_escape ~r/%(?![0-9a-fA-F]{2})/

  @impl true
  def init(opts) when is_list(opts), do: opts
  def init(_action), do: []

  @impl true
  def call(conn, opts) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    cond do
      not possible?(conn) or not origin?(conn, env) ->
        refuse(conn, 404, "Page not found")

      WebSockAdapter.UpgradeValidation.validate_upgrade(conn) != :ok ->
        CableProxy.bad_request(conn)

      true ->
        upgrade(conn, opts, env)
    end
  end

  def possible?(conn) do
    conn.method == "GET" and
      "upgrade" in String.split(String.downcase(header(conn, "connection")), ~r/ *, */) and
      String.downcase(header(conn, "upgrade")) == "websocket"
  end

  def origin?(conn, env) do
    origin = List.first(get_req_header(conn, "origin"))
    scheme = if RackScheme.ssl?(conn), do: "https", else: "http"

    origin == scheme <> "://" <> header(conn, "host") or
      (RailsSecret.rails_env(env) == "development" and is_binary(origin) and
         Regex.match?(@localhost, origin))
  end

  def protocol(offers), do: Enum.find(offers, &(&1 in @protocols))

  defp upgrade(conn, opts, env) do
    secret = Keyword.get_lazy(opts, :secret, &RailsSecret.fetch/0)
    clock = if now = opts[:now], do: fn -> now end, else: &DateTime.utc_now/0

    self_hosted =
      Keyword.get_lazy(opts, :self_hosted, fn ->
        LayoutAssigns.self_hosted?(%{"SELF_HOSTED" => env["SELF_HOSTED"]})
      end)

    state = %{
      identity: identity(conn, secret, clock.()),
      context: %{secret: secret, now: clock, self_hosted: self_hosted},
      beat_ms: Keyword.get(opts, :beat_ms, 3_000),
      silent_ms: Keyword.get(opts, :silent_ms, 60_000),
      subs: %{},
      bus: nil
    }

    Logger.info("[Cable] Phoenix upgraded /cable")

    conn
    |> put_protocol()
    |> WebSockAdapter.upgrade(DawarichWeb.Cable.Socket, state, CableProxy.upgrade_options())
    |> halt()
  end

  defp identity(conn, secret, now) do
    case query(conn.query_string) do
      {:ok, params} ->
        unlocked? = &SharedLinkCookie.unlocked?(conn, &1, now, secret)
        user = RailsAuth.session_user(conn, secret: secret, now: now)
        Identity.resolve(user, params["share_id"], unlocked?, now)

      :error ->
        :silent
    end
  rescue
    error ->
      Logger.warning("[Cable] connect failed: #{inspect(error.__struct__)}")
      :silent
  end

  defp query(string) do
    if Regex.match?(@bad_escape, string),
      do: :error,
      else: {:ok, Plug.Conn.Query.decode(string)}
  rescue
    Plug.Conn.InvalidQueryError -> :error
  end

  defp put_protocol(conn) do
    offers =
      conn
      |> get_req_header("sec-websocket-protocol")
      |> Enum.join(", ")
      |> String.split(~r/ *, */)

    case protocol(offers) do
      nil -> conn
      chosen -> put_resp_header(conn, "sec-websocket-protocol", chosen)
    end
  end

  defp header(conn, name), do: conn |> get_req_header(name) |> Enum.join(", ")

  defp refuse(conn, status, body),
    do: conn |> put_resp_content_type("text/plain") |> send_resp(status, body) |> halt()
end
