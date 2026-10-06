defmodule Dawarich.Front.NativeCommand do
  @moduledoc false

  alias Dawarich.Front.Command
  alias Dawarich.RailsSecret

  def parse(argv, env) do
    argv = unbundle(argv)

    result =
      if is_list(argv) and Enum.all?(argv, &is_binary/1),
        do: command(argv, env),
        else: {:error, "unsupported argv"}

    case result do
      {:error, _} ->
        {:error,
         "#{label(argv)} command is unsupported or has invalid arguments; use dawarich start, dawarich migrate, dawarich seeds, or dawarich help"}

      plan ->
        plan
    end
  end

  defp unbundle(["bundle", "exec" | argv]), do: argv
  defp unbundle(argv), do: argv

  defp label([rails, action | _]) when rails in ["rails", "bin/rails"] do
    if action in ~w(server s runner console db:migrate db:seed),
      do: "Rails #{action}",
      else: "Rails"
  end

  defp label(["puma" | _]), do: "Puma"
  defp label(["sidekiq" | _]), do: "Sidekiq"
  defp label(["rake" | _]), do: "Rake"
  defp label(["dawarich" | _]), do: "Native"
  defp label(_argv), do: "Legacy"

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

  defp command(["puma" | args], env) do
    with {:ok, opts} <-
           options(args, %{
             "-p" => :port,
             "--port" => :port,
             "-b" => :bind,
             "--bind" => :bind,
             "-C" => :config,
             "--config" => :config
           }),
         true <- Map.get(opts, :config, []) in [[], ["config/puma.rb"]] do
      puma_listener(opts, env)
    else
      _ -> {:error, "unsupported argv"}
    end
  end

  defp command(["sidekiq" | args], _env) do
    with {:ok, opts} <- options(args, %{"-C" => :config, "--config" => :config}),
         true <- Map.get(opts, :config, []) in [[], ["config/sidekiq.yml"]] do
      :sidekiq_idle
    else
      _ -> {:error, "unsupported argv"}
    end
  end

  defp command([rails, "db:migrate"], _env) when rails in ["rails", "bin/rails"], do: :migrate
  defp command([rails, "db:seed"], _env) when rails in ["rails", "bin/rails"], do: :seeds
  defp command(["dawarich", "start"], env), do: listener(%{}, env, "0.0.0.0")
  defp command(["dawarich", "migrate"], _env), do: :migrate
  defp command(["dawarich", "seeds"], _env), do: :seeds

  defp command(["dawarich", "migrate", "status"], _env), do: {:cli, ["migrate", "status"]}

  defp command(["dawarich", action | _args], _env) when action in ["seeds", "migrate"],
    do: {:error, "unsupported argv"}

  defp command(["dawarich", action, body], _env) when action in ["eval", "rpc"] and body != "",
    do: {:release, [action, body]}

  defp command(["dawarich", "remote"], _env), do: {:release, ["remote"]}

  defp command(["dawarich" | args], _env) do
    case Dawarich.CLI.resolve(args) do
      {:ok, _, _} -> {:cli, args}
      _ -> {:error, "unsupported argv"}
    end
  end

  defp command(_argv, _env), do: {:error, "unsupported argv"}

  defp puma_listener(%{bind: [bind]} = opts, _env) when not is_map_key(opts, :port) do
    case Regex.run(~r/\Atcp:\/\/(\[[^\]]+\]|[^:\/?#@]+):([0-9]+)\z/, bind) do
      [_, host, port] -> listener(%{binding: [host], port: [port]}, %{}, "0.0.0.0")
      _ -> {:error, "invalid listener"}
    end
  end

  defp puma_listener(opts, env) do
    if not Map.has_key?(opts, :bind) and length(Map.get(opts, :port, [])) <= 1,
      do: listener(opts, env, "0.0.0.0"),
      else: {:error, "invalid listener"}
  end

  defp listener(opts, env, default_host) do
    host = List.last(opts[:binding] || []) || present(env["BINDING"]) || default_host
    port = List.last(opts[:port] || []) || present(env["PORT"]) || "3000"

    bracketed? = String.contains?(host, ["[", "]"])

    result =
      if not bracketed? or Regex.match?(~r/\A\[[^\[\]]+\]\z/, host),
        do: Command.listen_address(host, port)

    case result do
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
            {key, arg |> binary_part(2, byte_size(arg) - 2) |> String.replace_prefix("=", "")}

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
