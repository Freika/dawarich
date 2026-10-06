defmodule Dawarich.MapMatching.Processor do
  alias Dawarich.MapMatching.{Composer, Input, QualityPolicy}
  alias Dawarich.MapMatching.Atlas.Client

  @stats [
    matched: :matched,
    interpolated: :interpolated,
    unmatched: :unmatched,
    segments: :segments,
    mean_distance: :mean_distance_from_trace_point,
    p95_distance: :p95_distance_from_trace_point,
    max_distance: :max_distance_from_trace_point,
    confidence_score: :confidence_score,
    raw_score: :raw_score
  ]
  @codes ~w(invalid_input invalid_request provider_invalid invalid_url connection_failed capacity rate_limited unavailable timeout http_error malformed_response)

  def call(input, client \\ Client) do
    if Input.eligible?(input) do
      client =
        if client == Client,
          do: Application.get_env(:dawarich, :map_matching_client, client),
          else: client

      input.portions
      |> Enum.reduce_while({:ok, []}, fn portion, {:ok, outcomes} ->
        case process(portion, client) do
          {:ok, outcome} -> {:cont, {:ok, [outcome | outcomes]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> result()
    else
      {:ok, skipped(input)}
    end
  end

  def skipped(input) do
    %{
      status: :skipped,
      path: nil,
      data: diagnostics(Enum.map(input.portions, &fallback(&1, "unsupported")))
    }
  end

  defp process(portion, client) do
    cond do
      not Input.eligible?(portion) ->
        {:ok, fallback(portion, "unsupported")}

      length(portion.points) > 10_000 ->
        {:ok, fallback(portion, "rejected", ["too_many_points"])}

      true ->
        payload = %{
          shape: Enum.map(portion.points, &Input.Point.atlas_shape/1),
          costing: portion.atlas_mode
        }

        case match(client, payload) do
          {:ok, response} ->
            {:ok, decide(portion, response)}

          {:error, %{status: status, transient?: false} = error} when status in [400, 422] ->
            {:ok, fallback(portion, "rejected", [error_code(error.code)])}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp match({client, url}, payload) when is_function(client, 2), do: client.(url, payload)
  defp match({client, url}, payload), do: apply(client, :match, [url, payload])
  defp match(client, payload) when is_function(client, 2), do: client.(nil, payload)

  defp match(client, payload) do
    url = apply(Dawarich.Experimental, :value, [:atlas_url])
    apply(client, :match, [url, payload])
  end

  defp decide(portion, response) do
    geometry = value(response, :geometry)
    stats = value(response, :stats) || %{}

    decision =
      QualityPolicy.call(
        geometry: geometry,
        stats: stats,
        input_point_count: length(portion.points)
      )

    outcome =
      if decision.accepted do
        coordinates = value(geometry, :coordinates)
        lines = if value(geometry, :type) == "LineString", do: [coordinates], else: coordinates
        %{accepted: true, lines: lines, diagnostic: diagnostic(portion, "accepted", [], stats)}
      else
        fallback(portion, "rejected", decision.reasons, stats)
      end

    Map.put(outcome, :provider, value(response, :provider) || %{})
  end

  defp fallback(portion, result, reasons \\ [], stats \\ %{}) do
    %{
      accepted: false,
      lines: [Input.original_coordinates(portion)],
      diagnostic: diagnostic(portion, result, reasons, stats)
    }
  end

  defp diagnostic(portion, result, reasons, stats) do
    %{
      transportation_mode: portion.transportation_mode,
      atlas_mode: portion.atlas_mode,
      result: result,
      reasons: reasons,
      point_count: length(portion.points),
      stats: compact_stats(stats)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp compact_stats(stats) do
    for {key, source} <- @stats,
        number = value(stats, source),
        is_number(number),
        into: %{},
        do: {key, number}
  end

  defp result({:error, error}), do: {:error, error}

  defp result({:ok, reversed}) do
    outcomes = Enum.reverse(reversed)
    accepted = Enum.count(outcomes, & &1.accepted)

    status =
      cond do
        accepted == 0 -> :rejected
        accepted == length(outcomes) -> :matched
        true -> :partial
      end

    path = if accepted > 0, do: Composer.call(Enum.flat_map(outcomes, & &1.lines))
    {:ok, %{status: status, path: path, data: diagnostics(outcomes)}}
  end

  defp diagnostics(outcomes) do
    provider = Enum.find_value(outcomes, %{}, &Map.get(&1, :provider))

    %{
      schema_version: 1,
      policy_version: QualityPolicy.version(),
      provider: Map.merge(%{name: "atlas"}, compact_provider(provider)),
      segments: Enum.map(outcomes, & &1.diagnostic),
      error: nil
    }
  end

  defp compact_provider(provider) do
    for key <- [:version, :revision],
        token = value(provider, key),
        is_binary(token),
        into: %{},
        do: {key, token}
  end

  defp error_code(code) when code in @codes, do: code
  defp error_code(_), do: "provider_error"
  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
