defmodule Dawarich.Front.NativeCommand do
  @moduledoc false

  alias Dawarich.Front.Command
  alias Dawarich.RailsSecret

  def parse(["bundle", "exec" | argv], env), do: command(argv, env)
  def parse(argv, env), do: command(argv, env)

  defp command([rails, server | args], env)
       when rails in ["rails", "bin/rails"] and server in ["server", "s"] do
    with {:ok, opts} <-
           options(args, %{
             "-p" => :port,
             "--port" => :port,
             "-b" => :binding,
             "--binding" => :binding
           }) do
      host = if RailsSecret.rails_env(env) == "development", do: "localhost", else: "0.0.0.0"
      listener(opts, env, host)
    end
  end

  defp command(_argv, _env), do: {:error, "unsupported argv"}

  defp listener(opts, env, default_host) do
    host = List.last(opts[:binding] || []) || present(env["BINDING"]) || default_host
    port = List.last(opts[:port] || []) || present(env["PORT"]) || "3000"

    case Command.listen_address(host, port) do
      {:ok, address} -> {:web, address}
      _ -> {:error, "invalid listener"}
    end
  end

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp options(args, flags), do: options(args, flags, %{})
  defp options([], _flags, opts), do: {:ok, opts}

  defp options([flag, value | tail], flags, opts) when is_map_key(flags, flag) do
    options(tail, flags, Map.update(opts, flags[flag], [value], &(&1 ++ [value])))
  end

  defp options([arg | tail], flags, opts) do
    attached =
      Enum.find_value(flags, fn {flag, key} ->
        cond do
          String.starts_with?(flag, "--") and String.starts_with?(arg, flag <> "=") ->
            {key, String.replace_prefix(arg, flag <> "=", "")}

          byte_size(flag) == 2 and String.starts_with?(arg, flag) and byte_size(arg) > 2 ->
            {key, binary_part(arg, 2, byte_size(arg) - 2)}

          true ->
            nil
        end
      end)

    case attached do
      {key, value} -> options(tail, flags, Map.update(opts, key, [value], &(&1 ++ [value])))
      nil -> {:error, "unsupported argv"}
    end
  end
end
