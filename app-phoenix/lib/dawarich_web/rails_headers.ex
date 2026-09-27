defmodule DawarichWeb.RailsHeaders do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  @headers %{
    "x-frame-options" => "SAMEORIGIN",
    "x-xss-protection" => "0",
    "x-content-type-options" => "nosniff",
    "x-permitted-cross-domain-policies" => "none",
    "referrer-policy" => "strict-origin-when-cross-origin"
  }

  def init(opts), do: opts

  def call(conn, _opts),
    do:
      Enum.reduce(@headers, conn, fn {name, value}, acc -> put_resp_header(acc, name, value) end)
end
