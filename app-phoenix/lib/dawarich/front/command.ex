defmodule Dawarich.Front.Command do
  @moduledoc false

  alias Dawarich.RailsSecret

  @loopback "127.0.0.1"

  defdelegate native(argv, env), to: Dawarich.Front.NativeCommand, as: :parse

  def listen_address(host, value) do
    with {:ok, port} <- port(value), {:ok, ip} <- ip(host), do: {:ok, {ip, port}}
  end

  def parse(["bundle", "exec", rails, server | args], env, upstream, _ipv6?)
      when rails in ["bin/rails", "rails"] and server in ["server", "s"] do
    {ports, args} = take(args, "-p", "--port")
    {hosts, args} = take(args, "-b", "--binding")

    with {:ok, port} <- port(List.last(ports) || present(env["PORT"]) || "3000"),
         {:ok, ip} <- ip(List.last(hosts) || present(env["BINDING"]) || rails_host(env)) do
      loopback = ["-b", @loopback, "-p", Integer.to_string(upstream)]
      {:ok, {ip, port}, ["bundle", "exec", rails, server | args] ++ loopback}
    end
  end

  def parse(["bundle", "exec", "puma" | args], env, upstream, ipv6?) do
    {ports, args} = take(args, "-p", "--port")
    {binds, args} = take(args, "-b", "--bind")

    with {:ok, address} <- puma_address(ports, binds, args, env, ipv6?) do
      {:ok, address,
       ["bundle", "exec", "puma" | args] ++ ["-b", "tcp://#{@loopback}:#{upstream}"]}
    end
  end

  def parse(_argv, _env, _upstream, _ipv6?),
    do: {:direct, "the server command is not one Phoenix can front"}

  defp puma_address([], [], args, env, ipv6?) do
    case take(args, "-C", "--config") do
      {config, _} when config in [[], ["config/puma.rb"]] ->
        with {:ok, port} <- port(present(env["PORT"]) || "3000"), do: {:ok, {any(ipv6?), port}}

      _ ->
        {:direct, "Puma reads a configuration file whose listeners Phoenix does not know"}
    end
  end

  defp puma_address([port], [], _args, _env, ipv6?) do
    with {:ok, port} <- port(port), do: {:ok, {any(ipv6?), port}}
  end

  defp puma_address([], [bind], _args, _env, _ipv6?) do
    case URI.parse(bind) do
      %URI{scheme: "tcp", host: host, port: port} when is_binary(host) and is_integer(port) ->
        with {:ok, ip} <- ip(host), do: {:ok, {ip, port}}

      _ ->
        {:direct, "Puma binds #{bind}, which Phoenix does not front"}
    end
  end

  defp puma_address(_ports, _binds, _args, _env, _ipv6?),
    do: {:direct, "Puma is asked for several listeners"}

  defp rails_host(env) do
    if RailsSecret.rails_env(env) == "development", do: "localhost", else: "0.0.0.0"
  end

  defp any(true), do: {0, 0, 0, 0, 0, 0, 0, 0}
  defp any(false), do: {0, 0, 0, 0}

  defp ip("localhost"), do: {:ok, {127, 0, 0, 1}}

  defp ip(value) do
    address =
      value |> String.trim_leading("[") |> String.trim_trailing("]") |> String.to_charlist()

    case :inet.parse_address(address) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> {:direct, "the listen address #{value} is not an IP address"}
    end
  end

  defp port(value) do
    case Integer.parse(value) do
      {port, ""} when port in 1..65_535 -> {:ok, port}
      _ -> {:direct, "the listen port #{value} is not a port number"}
    end
  end

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp take(args, short, long), do: take(args, short, long, [], [])

  defp take([], _short, _long, values, rest), do: {Enum.reverse(values), Enum.reverse(rest)}

  defp take([flag, value | tail], short, long, values, rest) when flag in [short, long],
    do: take(tail, short, long, [value | values], rest)

  defp take([arg | tail], short, long, values, rest) do
    case attached(arg, short, long) do
      nil -> take(tail, short, long, values, [arg | rest])
      value -> take(tail, short, long, [value | values], rest)
    end
  end

  defp attached(arg, short, long) do
    cond do
      String.starts_with?(arg, long <> "=") ->
        String.replace_prefix(arg, long <> "=", "")

      String.starts_with?(arg, short) and byte_size(arg) > 2 ->
        binary_part(arg, 2, byte_size(arg) - 2)

      true ->
        nil
    end
  end
end
