defmodule DawarichWeb.RailsSession do
  @moduledoc false

  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret}
  alias DawarichWeb.ForceSSL

  @name "_dawarich_session"
  @writable ["flash", "_csrf_token", "locale"]
  @max_size 4096

  defmodule Overflow do
    defexception [:size]

    @impl true
    def message(%{size: size}), do: "_dawarich_session cookie overflowed with size #{size} bytes"
  end

  def put(conn, changes) do
    validate!(changes)
    conn = fetch_cookies(conn)

    case rewrite(conn.cookies[@name], changes, RailsSecret.fetch()) do
      {:ok, value} ->
        put_resp_cookie(conn, @name, value,
          path: "/",
          http_only: true,
          same_site: "Lax",
          secure: ForceSSL.enabled?()
        )

      :unchanged ->
        conn
    end
  end

  def rewrite(cookie, changes, secret) do
    validate!(changes)
    current = read(cookie, secret)
    session = Enum.reduce(changes, current, &apply_change/2)

    if session == current, do: :unchanged, else: {:ok, encode(session, secret)}
  end

  defp validate!(changes) when is_map(changes) do
    case Map.keys(changes) -- @writable do
      [] ->
        :ok

      keys ->
        raise ArgumentError, "only #{inspect(@writable)} may be written, got #{inspect(keys)}"
    end
  end

  defp validate!(_changes), do: raise(ArgumentError, "changes must be a map")

  defp read(cookie, secret) when is_binary(cookie) do
    case RailsCookies.decrypt(cookie, @name, secret, DateTime.utc_now()) do
      {:ok, %{} = session} -> session
      _ -> %{}
    end
  end

  defp read(_cookie, _secret), do: %{}

  defp apply_change({key, nil}, session), do: Map.delete(session, key)
  defp apply_change({key, value}, session), do: Map.put(session, key, value)

  defp encode(session, secret) do
    value = RailsCookies.encrypt(session, @name, secret)
    size = byte_size(@name) + byte_size(URI.decode_www_form(value))

    if size > @max_size, do: raise(Overflow, size: size), else: value
  end
end
