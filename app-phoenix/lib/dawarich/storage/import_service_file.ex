defmodule Dawarich.Storage.ImportServiceFile do
  @moduledoc false
  @required ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET)
  @s3_condition "if !Rails.env.test? && ENV['AWS_ACCESS_KEY_ID'] && ENV['AWS_SECRET_ACCESS_KEY'] && ENV['AWS_REGION'] && ENV['AWS_BUCKET']"
  @endpoint_assignment "endpoint_url = ENV['AWS_ENDPOINT_URL'] || ENV['AWS_ENDPOINT']"

  def parse(text, env, root) do
    state = %{services: %{}, name: nil, conditions: [], env: env, root: root, invalid: false}
    state = text |> String.split("\n") |> Enum.reduce(state, &line/2)
    if state.invalid or state.conditions != [], do: %{}, else: state.services
  end

  defp line(raw, state) do
    trimmed = String.trim(raw)

    cond do
      trimmed == "" or String.starts_with?(trimmed, "#") ->
        state

      String.starts_with?(trimmed, "<%") and not String.starts_with?(trimmed, "<%=") ->
        directive(trimmed, state)

      not Enum.all?(state.conditions) ->
        state

      match = Regex.run(~r/\A([A-Za-z0-9_-]+):\s*\z/, raw) ->
        [_, name] = match
        %{state | name: name, services: Map.put(state.services, name, %{})}

      match = Regex.run(~r/\A  ([a-z_]+):\s*(.*?)\s*\z/, raw) ->
        [_, key, value] = match
        put(state, key, scalar(value, state))

      true ->
        put(state, "unsupported", nil)
    end
  end

  defp directive(line, state) do
    case Regex.run(~r/\A<%\s*(.*?)\s*%>\z/, line) do
      [_, "end"] ->
        if state.conditions == [],
          do: %{state | invalid: true},
          else: %{state | conditions: Enum.drop(state.conditions, 1)}

      [_, @endpoint_assignment] ->
        state

      [_, @s3_condition] ->
        rails_env =
          present(state.env["RAILS_ENV"]) || present(state.env["RACK_ENV"]) || "development"

        enabled = rails_env != "test" and Enum.all?(@required, &is_binary(state.env[&1]))
        %{state | conditions: [enabled | state.conditions]}

      [_, "if endpoint_url"] ->
        %{state | conditions: [endpoint(state.env) != nil | state.conditions]}

      [_, "if " <> _] ->
        %{state | conditions: [false | state.conditions]}

      _ ->
        %{state | invalid: true}
    end
  end

  defp put(%{name: nil} = state, _, _), do: state

  defp put(state, key, value),
    do: update_in(state.services[state.name], &Map.put(&1, key, value))

  defp scalar(value, state) do
    case Regex.run(~r/\A<%=\s*(.*?)\s*%>\z/, value) do
      [_, expression] -> expression(expression, state)
      nil -> literal(value)
    end
  end

  defp expression("endpoint_url", state), do: endpoint(state.env)

  defp expression(expression, state) do
    cond do
      match = Regex.run(~r/\AENV\.fetch\(["']([A-Z0-9_]+)["']\)\z/, expression) ->
        [_, key] = match
        present(state.env[key])

      match = Regex.run(~r/\ARails\.root\.join\((.*)\)\z/, expression) ->
        [_, args] = match
        parts = String.split(args, ",") |> Enum.map(&quoted/1)

        if Enum.all?(parts, &(is_binary(&1) and &1 != "")),
          do:
            Enum.reduce(parts, state.root, fn part, root ->
              if Path.type(part) == :absolute,
                do: Path.expand(part),
                else: Path.expand(Path.join(root, part))
            end)

      true ->
        nil
    end
  end

  defp quoted(value) do
    case Regex.run(~r/\A\s*["']([^"'\\]*)["']\s*\z/, value) do
      [_, literal] -> literal
      nil -> nil
    end
  end

  defp literal(value) do
    cond do
      String.starts_with?(value, ["\"", "'"]) -> quoted(value)
      value == "" or String.contains?(value, ["<%", "&", "*", "{", "}", "[", "]", " #"]) -> nil
      true -> value
    end
  end

  defp endpoint(env), do: env["AWS_ENDPOINT_URL"] || env["AWS_ENDPOINT"]
  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value
end
