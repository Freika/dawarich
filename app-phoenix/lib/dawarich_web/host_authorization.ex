defmodule DawarichWeb.HostAuthorization do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Dawarich.RailsSecret
  alias DawarichWeb.Origin

  @env ~w(RAILS_ENV RACK_ENV APPLICATION_HOSTS RAILS_DEVELOPMENT_HOSTS)
  @ip [
    ~r/\A(\d+\.\d+\.\d+\.\d+)(?::\d+)?\z/,
    ~r/\A([a-f0-9]*:[a-f0-9.:]+)\z/i,
    ~r/\A\[([a-f0-9]*:[a-f0-9.:]+)\](?::\d+)?\z/i
  ]

  def boot_config(env \\ Map.new(@env, &{&1, System.get_env(&1)})) do
    application = split(env["APPLICATION_HOSTS"] || "localhost")

    case RailsSecret.rails_env(env) do
      rails when rails in ["production", "staging"] ->
        Enum.map(application, &Origin.host_pattern/1)

      "development" ->
        development = [".localhost", ".test" | split(env["RAILS_DEVELOPMENT_HOSTS"] || "")]
        [:ip | Enum.map(development ++ application, &Origin.host_pattern/1)]

      _ ->
        []
    end
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.get_env(:dawarich, :allowed_hosts, []) do
      [] ->
        conn

      hosts ->
        case Enum.reject(requested(conn), &allowed?(&1, hosts)) do
          [] -> conn
          blocked -> block(conn, blocked)
        end
    end
  end

  defp split(value) do
    value
    |> String.split(",")
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.map(&Dawarich.ReleaseMigration.ruby_strip/1)
  end

  defp requested(conn) do
    host = conn |> get_req_header("host") |> List.first()

    forwarded =
      conn
      |> get_req_header("x-forwarded-host")
      |> Enum.join(", ")
      |> String.split(~r/,\s?/)
      |> Enum.reverse()
      |> Enum.drop_while(&(&1 == ""))
      |> List.first()

    if forwarded in [nil, ""] or String.trim(forwarded) == "",
      do: [host],
      else: [host, forwarded]
  end

  defp allowed?(nil, _hosts), do: false
  defp allowed?(host, hosts), do: Enum.any?(hosts, &matches?(host, &1))

  defp matches?(host, :ip) do
    address =
      Enum.find_value(@ip, host, fn pattern ->
        with [captured] <- Regex.run(pattern, host, capture: :all_but_first), do: captured
      end)

    match?({:ok, _}, :inet.parse_strict_address(:binary.bin_to_list(address)))
  end

  defp matches?(host, pattern), do: host =~ pattern

  defp block(conn, blocked) do
    Logger.error("[#{inspect(__MODULE__)}] Blocked hosts: #{Enum.join(blocked, ", ")}")

    xhr? =
      conn
      |> get_req_header("x-requested-with")
      |> Enum.join(", ")
      |> String.match?(~r/XMLHttpRequest/i)

    type = if xhr?, do: "text/plain", else: "text/html"

    %{conn | resp_headers: [{"content-type", type <> "; charset=UTF-8"}]}
    |> send_resp(403, "")
    |> halt()
  end
end
