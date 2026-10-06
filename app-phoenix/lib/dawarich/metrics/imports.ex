defmodule Dawarich.Metrics.Imports do
  @moduledoc false
  import Telemetry.Metrics

  @in_flight """
  SELECT additional_data_extraction_status, additional_data_extraction
  FROM imports WHERE additional_data_extraction_status IN (1, 2)
  """
  @states %{1 => "pending", 2 => "running"}
  @stale 21_600

  def sample(repo \\ Dawarich.Jobs.repo()) do
    {:ok, {oldest, stalled}} =
      repo.transaction(fn ->
        repo.query!("SET LOCAL statement_timeout = '500ms'", [], log: false)
        [[now]] = repo.query!("SELECT now()", [], log: false).rows
        repo.query!(@in_flight, [], log: false).rows
        |> Enum.reduce({%{"pending" => 0, "running" => 0}, 0}, fn [state, payload], {oldest, stalled} ->
          case started(payload) do
            nil ->
              {oldest, stalled + 1}
            started ->
              age = DateTime.diff(now, started)
              oldest = Map.update!(oldest, @states[state], &max(&1, age))
              {oldest, stalled + if(age >= @stale, do: 1, else: 0)}
          end
        end)
      end)

    for {state, age} <- oldest,
      do: :telemetry.execute([:dawarich, :imports, :age], %{age: age}, %{state: state})
    :telemetry.execute([:dawarich, :imports, :stalled], %{count: stalled}, %{})
  end

  def collect(repo) do
    if Dawarich.Metrics.enabled?() do
      sample(repo)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  def definitions do
    [
      last_value("dawarich_imports_extraction_oldest_age_seconds",
        event_name: [:dawarich, :imports, :age], measurement: :age, tags: [:state]),
      last_value("dawarich_imports_extractions_stalled",
        event_name: [:dawarich, :imports, :stalled], measurement: :count)
    ]
  end

  defp started(%{"started_at" => value}) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, stamp, _offset} -> stamp
      _ -> nil
    end
  end

  defp started(_), do: nil
end
