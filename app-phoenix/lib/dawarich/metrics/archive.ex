defmodule Dawarich.Metrics.Archive do
  @moduledoc false
  import Telemetry.Metrics

  def track(operation, fun, points \\ fn _ -> 0 end) do
    result = fun.()
    status = if match?({:error, _}, result), do: "failure", else: "success"
    count = points.(result)
    if operation != "archive" or count > 0, do: operation(operation, status)
    if count > 0, do: emit(:points, %{count: count}, %{operation: point_operation(operation)})
    result
  rescue
    exception ->
      operation(operation, "failure")
      reraise exception, __STACKTRACE__
  end

  def verify(fun) do
    started = System.monotonic_time()

    try do
      result = track("verify", fun)
      status = if result == :ok, do: "success", else: "failure"
      emit(:verify, %{duration: seconds(started)}, %{status: status})

      case result do
        {:error, check} -> emit(:failure, %{count: 1}, %{check: check})
        _ -> :ok
      end

      result
    rescue
      exception ->
        emit(:verify, %{duration: seconds(started)}, %{status: "failure"})
        emit(:failure, %{count: 1}, %{check: "exception"})
        reraise exception, __STACKTRACE__
    end
  end

  def operation(operation, status),
    do: emit(:operation, %{count: 1}, %{operation: operation, status: status})

  def sizes(message, source_bytes) do
    emit(:size, %{size: byte_size(message)}, %{})
    emit(:ratio, %{ratio: byte_size(message) / max(source_bytes, 1)}, %{})
  end

  def mismatch(user, year, month, difference) do
    emit(:mismatch, %{count: 1}, %{year: year, month: month})
    emit(:difference, %{difference: abs(difference)}, %{user_id: user})
  end

  def definitions do
    [
      sum("dawarich_archive_operations_total",
        event_name: event(:operation),
        measurement: :count,
        tags: [:operation, :status]
      ),
      sum("dawarich_archive_points_total",
        event_name: event(:points),
        measurement: :count,
        tags: [:operation]
      ),
      sum("dawarich_archive_count_mismatches_total",
        event_name: event(:mismatch),
        measurement: :count,
        tags: [:year, :month]
      ),
      last_value("dawarich_archive_count_difference",
        event_name: event(:difference),
        measurement: :difference,
        tags: [:user_id]
      ),
      distribution("dawarich_archive_compression_ratio",
        event_name: event(:ratio),
        measurement: :ratio,
        reporter_options: [buckets: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]]
      ),
      distribution("dawarich_archive_size_bytes",
        event_name: event(:size),
        measurement: :size,
        reporter_options: [
          buckets: [1_000_000, 10_000_000, 50_000_000, 100_000_000, 500_000_000, 1_000_000_000]
        ]
      ),
      distribution("dawarich_archive_verification_duration_seconds",
        event_name: event(:verify),
        measurement: :duration,
        tags: [:status],
        reporter_options: [buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60]]
      ),
      sum("dawarich_archive_verification_failures_total",
        event_name: event(:failure),
        measurement: :count,
        tags: [:check]
      )
    ]
  end

  defp seconds(started),
    do: (System.monotonic_time() - started) / System.convert_time_unit(1, :second, :native)

  defp point_operation("archive"), do: "added"
  defp point_operation("clear"), do: "removed"
  defp point_operation("restore"), do: "restored"

  defp emit(event, measurements, labels),
    do: :telemetry.execute(event(event), measurements, labels)

  defp event(name), do: [:dawarich, :archive, name]
end
