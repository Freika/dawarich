defmodule Dawarich.Redis do
  @moduledoc false

  @name __MODULE__

  def child_specs(config \\ Application.get_env(:dawarich, :redis, [])) do
    case config[:url] do
      url when is_binary(url) and url != "" ->
        [Redix.child_spec({url, options(url, config[:database])})]

      _ ->
        []
    end
  end

  def options(url, database) do
    base = [name: @name, database: database, sync_connect: false, exit_on_disconnection: false]
    if String.starts_with?(url, "rediss://"), do: base ++ [socket_opts: tls()], else: base
  end

  def command(args, conn \\ @name) do
    Redix.command(conn, args, timeout: 5_000)
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp tls do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end
end
