defmodule DawarichWeb.Api.AccountManager do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Accounts, AppVersion}
  alias DawarichWeb.Api.Headers

  def init(opts), do: opts

  def call(conn, _opts) do
    supplied = conn |> get_req_header("x-webhook-secret") |> Enum.join(", ")
    secret = System.get_env("SUBSCRIPTION_WEBHOOK_SECRET", "")

    conn
    |> frame()
    |> assign(:manager_secret_valid, Plug.Crypto.secure_compare(supplied, secret))
  end

  defp frame(conn) do
    key = conn.assigns.api_params["api_key"] || bearer(conn)
    user = if is_binary(key) and key != "", do: Accounts.by_api_key(key)
    id = conn |> get_req_header("x-request-id") |> Enum.join(", ") |> String.trim()

    id =
      if id == "",
        do: Ecto.UUID.generate(),
        else: id |> String.replace(~r/[^\w\-@]/, "") |> String.slice(0, 255)

    conn
    |> assign(:api_started, System.monotonic_time())
    |> assign(:api_request_id, id)
    |> assign(:api_headers, Headers.dawarich(user != nil, AppVersion.current()))
    |> assign(
      :api_vary,
      get_req_header(conn, "accept") != [] and not Map.has_key?(conn.assigns.api_params, "format")
    )
    |> assign(:api_if_none_match, conn |> get_req_header("if-none-match") |> Enum.join(", "))
  end

  defp bearer(conn) do
    case Regex.run(
           ~r/\ABearer\s+(\S+)\z/i,
           conn |> get_req_header("authorization") |> Enum.join(", "),
           capture: :all_but_first
         ) do
      [key] -> key
      _ -> nil
    end
  end
end
