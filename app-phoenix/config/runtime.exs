import Config

env_integer = fn name, default ->
  case System.get_env(name) do
    value when value in [nil, ""] -> default
    value -> String.to_integer(value)
  end
end

ssl_options = fn mode, root_cert ->
  case mode do
    "require" -> [verify: :verify_none]
    mode when mode in ["verify-ca", "verify-full"] and root_cert in [nil, ""] -> true
    mode when mode in ["verify-ca", "verify-full"] -> [cacertfile: root_cert]
    _ -> false
  end
end

socket_options = fn host ->
  address = String.to_charlist(host || "localhost")

  case {:inet.getaddr(address, :inet), :inet.getaddr(address, :inet6)} do
    {{:error, _}, {:ok, _}} -> [:inet6]
    _ -> []
  end
end

oban_node = fn hostname ->
  if is_binary(hostname) and hostname =~ ~r/\A\S+\z/,
    do: hostname,
    else: :inet.gethostname() |> elem(1) |> to_string()
end

if config_env() != :test do
  default_database =
    if config_env() == :prod, do: "dawarich_production", else: "dawarich_development"

  {repo_config, host, url_sslmode} =
    case System.get_env("DATABASE_URL") do
      url when url in [nil, ""] ->
        host = System.get_env("DATABASE_HOST", "localhost")

        {[
           hostname: host,
           port: env_integer.("DATABASE_PORT", 5432),
           username: System.get_env("DATABASE_USERNAME"),
           password: System.get_env("DATABASE_PASSWORD"),
           database: System.get_env("DATABASE_NAME", default_database)
         ], host, nil}

      url ->
        uri = url |> String.replace(~r{^postgis://}, "postgres://") |> URI.parse()
        query = URI.decode_query(uri.query || "")
        rest = query |> Map.delete("sslmode") |> URI.encode_query()

        {[url: URI.to_string(%{uri | query: if(rest == "", do: nil, else: rest)})], uri.host,
         query["sslmode"]}
    end

  queues = [app_version_checking: 1, mailers: 2, trips: 2]

  config :dawarich,
         Dawarich.Repo,
         repo_config ++
           [
             ssl:
               ssl_options.(
                 url_sslmode || System.get_env("PGSSLMODE"),
                 System.get_env("PGSSLROOTCERT")
               ),
             socket_options: socket_options.(host),
             pool_size: Enum.sum(Keyword.values(queues)) + 3
           ]

  config :dawarich, Oban,
    node: oban_node.(System.get_env("HOSTNAME")),
    peer: Oban.Peers.Database,
    stager: {Oban.Stager, []},
    queues: queues,
    pruner: [max_age: {1, :day}],
    lifeline: [rescue_after: {60, :minute}],
    shutdown_grace_period: 12_000
end

case System.get_env("DAWARICH_RAILS_ARGS") do
  args when args in [nil, ""] ->
    :ok

  args ->
    config :dawarich,
           :rails_argv,
           args |> String.replace_suffix("\x1F", "") |> String.split("\x1F")
end
