defmodule DawarichWeb.HostAuthorization do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn
  import Dawarich.ReleaseMigration, only: [ruby_strip: 1]

  alias Dawarich.RailsSecret

  @env ~w(RAILS_ENV RACK_ENV APPLICATION_HOSTS)
  @ip [
    ~r/\A(\d+\.\d+\.\d+\.\d+)(?::\d+)?\z/,
    ~r/\A([a-f0-9]*:[a-f0-9.:]+)\z/i,
    ~r/\A\[([a-f0-9]*:[a-f0-9.:]+)\](?::\d+)?\z/i
  ]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    env = Keyword.get_lazy(opts, :env, fn -> Map.new(@env, &{&1, System.get_env(&1)}) end)

    case hosts(env) do
      [] -> conn
      hosts -> if Enum.all?(requested(conn), &allowed?(&1, hosts)), do: conn, else: blocked(conn)
    end
  end

  defp hosts(env) do
    list = split(env["APPLICATION_HOSTS"] || "localhost")

    case RailsSecret.rails_env(env) do
      rails when rails in ["production", "staging"] -> Enum.map(list, &pattern/1)
      "development" -> [:ip | Enum.map([".localhost", ".test" | list], &pattern/1)]
      _test -> []
    end
  end

  defp split(value),
    do:
      value
      |> String.split(",")
      |> Enum.reverse()
      |> Enum.drop_while(&(&1 == ""))
      |> Enum.reverse()
      |> Enum.map(&ruby_strip/1)

  defp pattern("." <> rest),
    do: Regex.compile!("\\A(?:[a-z0-9-]+\\.)?#{Regex.escape(rest)}(?::\\d+)?\\z", "i")

  defp pattern(host), do: Regex.compile!("\\A#{Regex.escape(host)}(?::\\d+)?\\z", "i")

  defp requested(conn) do
    origin = conn |> get_req_header("host") |> List.first()

    case conn
         |> get_req_header("x-forwarded-host")
         |> Enum.join(", ")
         |> String.split(~r/,\s?/)
         |> List.last() do
      forwarded when forwarded in [nil, ""] -> [origin]
      forwarded -> [origin, forwarded]
    end
  end

  defp allowed?(nil, _hosts), do: false
  defp allowed?(host, hosts), do: Enum.any?(hosts, &host_matches?(host, &1))

  defp host_matches?(host, :ip),
    do: Enum.any?(@ip, &ip?(Regex.run(&1, host, capture: :all_but_first)))

  defp host_matches?(host, regex), do: host =~ regex

  defp ip?([address]), do: match?({:ok, _}, :inet.parse_address(String.to_charlist(address)))
  defp ip?(_nil), do: false

  defp blocked(conn) do
    type =
      if conn |> get_req_header("x-requested-with") |> Enum.join() =~ ~r/XMLHttpRequest/i,
        do: "text/plain",
        else: "text/html"

    conn
    |> delete_resp_header("cache-control")
    |> put_resp_header("content-type", type <> "; charset=UTF-8")
    |> send_resp(403, "")
    |> halt()
  end
end
