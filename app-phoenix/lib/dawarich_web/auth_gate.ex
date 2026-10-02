defmodule DawarichWeb.AuthGate do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.Auth.RegistrationSetting
  alias DawarichWeb.AuthHandler

  @handlers [{"credentials", AuthHandler}]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case claimed(conn) do
      nil -> conn
      {flow, handler} -> handler.call(conn, options(flow, RegistrationSetting.fetch()))
    end
  end

  defp claimed(conn) do
    flows = Application.get_env(:dawarich, :phoenix_auth, [])

    if System.get_env("SELF_HOSTED") == "true" do
      Enum.find(@handlers, fn {flow, handler} -> flow in flows and handler.route?(conn) end)
    end
  end

  defp options("credentials", {:ok, registration}),
    do: [enabled: true, registration_enabled: registration]

  defp options("credentials", :error), do: [enabled: true]
end
