defmodule Dawarich.Metrics.Drain do
  @moduledoc false
  @sample ~r/\A([a-zA-Z_:][a-zA-Z0-9_:]*)(\{.*?\})?(\s+.*)\z/

  def config do
    case System.get_env("SIDEKIQ_METRICS_URL") do
      url when url in [nil, ""] ->
        nil

      url ->
        %{
          url: url,
          username: System.get_env("METRICS_USERNAME") || "",
          password: System.get_env("METRICS_PASSWORD") || ""
        }
    end
  end

  def scrape(local, config \\ config(), fetch \\ &fetch/1)
  def scrape(local, nil, _fetch), do: local

  def scrape(local, config, fetch) do
    case fetch.(config) do
      {:ok, remote} when is_binary(remote) and remote != "" -> merge(local, remote)
      _ -> local
    end
  rescue
    _ -> local
  catch
    :exit, _ -> local
  end

  def fetch(config) do
    authorization = "Basic " <> Base.encode64(config.username <> ":" <> config.password)

    request =
      {String.to_charlist(config.url), [{~c"authorization", String.to_charlist(authorization)}]}

    case :httpc.request(
           :get,
           request,
           [timeout: 5000, connect_timeout: 5000, autoredirect: false],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _, body}} -> {:ok, body}
      _ -> {:error, :unavailable}
    end
  end

  def merge(local, remote) do
    collisions = MapSet.intersection(identities(local), identities(remote))

    {lines, _seen} =
      Enum.reduce([{"web", local}, {"sidekiq", remote}], {[], MapSet.new()}, fn {process, body},
                                                                                acc ->
        Enum.reduce(String.split(body, "\n", trim: true), acc, fn line, {lines, seen} ->
          case String.split(line, " ", parts: 4) do
            ["#", kind, name | _] when kind in ["HELP", "TYPE"] ->
              key = {kind, name}

              if MapSet.member?(seen, key),
                do: {lines, seen},
                else: {[line | lines], MapSet.put(seen, key)}

            _ ->
              {[disambiguate(line, process, collisions) | lines], seen}
          end
        end)
      end)

    Enum.reverse(lines) |> Enum.join("\n") |> Kernel.<>("\n")
  end

  defp identities(body),
    do:
      body
      |> String.split("\n")
      |> Enum.map(&identity/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

  defp identity(line) do
    case Regex.run(@sample, line) do
      [_, name, labels, _] -> {name, if(labels == "{}", do: "", else: labels)}
      _ -> nil
    end
  end

  defp disambiguate(line, process, collisions) do
    if MapSet.member?(collisions, identity(line)) do
      [_, name, labels, value] = Regex.run(@sample, line)

      if Regex.match?(~r/[{,]process="/, labels) do
        line
      else
        label = ~s(process="#{process}")

        labels =
          if labels in ["", "{}"],
            do: "{#{label}}",
            else: "{#{label},#{String.slice(labels, 1..-1//1)}"

        name <> labels <> value
      end
    else
      line
    end
  end
end
