defmodule Dawarich.Imports.Tcx do
  @moduledoc false
  alias Dawarich.Imports.{
    ActivityType,
    GpxProgress,
    ImportTime,
    NormalBatch,
    XmlAmpersands,
    XmlInput
  }

  alias Dawarich.Imports.JsonStream.Spool
  alias Dawarich.Imports.Tcx.Handler
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Number
  alias Dawarich.Ingest.Ruby, as: DecimalNumber

  def call(path, import, context) do
    context = Map.put(context, :importer_name, "TCX")

    Spool.with_directory(context, fn dir ->
      input = Path.join(dir, "input.xml")
      objects = Path.join(dir, "objects")
      prepared = Path.join(dir, "prepared")
      XmlAmpersands.copy(path, input)
      parse(input, objects)

      File.open!(prepared, [:write, :binary, :raw], fn io ->
        for {sport, tp} <- Spool.stream(objects, [:raw]) do
          if attrs = point(tp, sport, import, context), do: Spool.write!(io, attrs)
        end
      end)

      clock = Map.update!(context, :now, &date_time/1)

      {batch, progress} =
        Enum.reduce(
          Spool.stream(prepared, [:raw]),
          {NormalBatch.new(import, context, :non_atomic), %{at: nil, index: nil}},
          fn attrs, {batch, progress} ->
            next = NormalBatch.push(batch, attrs)

            progress =
              if batch.size == 999,
                do: GpxProgress.record(import, next.inserted - batch.inserted, progress, clock),
                else: progress

            {next, progress}
          end
        )

      next = NormalBatch.finish(batch)

      if batch.size > 0,
        do: GpxProgress.record(import, next.inserted - batch.inserted, progress, clock)

      :ok
    end)
  end

  defp point(tp, sport, import, context) do
    position = tp["Position"]

    if not Number.blank?(position) do
      lat = position["LatitudeDegrees"]
      lon = position["LongitudeDegrees"]
      time = tp["Time"]

      unless Enum.any?([lat, lon, time], &Number.blank?/1) do
        alt = if tp["AltitudeMeters"], do: Number.to_f(tp["AltitudeMeters"]), else: nil
        now = if is_function(context.now, 0), do: context.now.(), else: context.now
        timestamp = ImportTime.parse(time, context.zone, date_time(now), context.repo) || 0
        now = if match?(%DateTime{}, now), do: DateTime.to_naive(now), else: now

        motion =
          if activity = ActivityType.map(sport), do: %{"activity_type" => activity}, else: %{}

        attrs = %{
          lonlat: "POINT(#{DecimalNumber.to_d(lon)} #{DecimalNumber.to_d(lat)})",
          timestamp: timestamp,
          altitude: alt,
          velocity: speed(tp),
          user_id: import.user_id,
          import_id: import.id,
          motion_data: motion,
          created_at: now,
          updated_at: now
        }

        if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, alt), else: attrs
      end
    end
  end

  defp speed(tp) do
    if extensions = tp["Extensions"] do
      tpx = extensions["TPX"]
      if is_map(tpx) and tpx["Speed"], do: Float.round(Number.to_f(tpx["Speed"]), 1), else: nil
    end
  end

  defp date_time(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp date_time(now), do: now

  defp parse(path, objects) do
    File.open!(objects, [:write, :binary, :raw], fn out ->
      File.open!(path, [:read, :binary, :raw], fn io ->
        checkpoint = make_ref()
        input = XmlInput.new(io) |> Map.put(:checkpoint, checkpoint)

        try do
          options = [
            :disallow_entities,
            external_entities: :none,
            event_fun: &Handler.event/3,
            event_state: Handler.new(out),
            continuation_fun: &XmlInput.next/1,
            continuation_state: input
          ]

          case :xmerl_sax_parser.stream(<<>>, options) do
            {:ok, _, rest} ->
              XmlInput.finish(rest, Process.get(checkpoint, input))

            {:fatal_error, error} when is_exception(error) ->
              raise error

            {:fatal_error, _, reason, _, _} ->
              raise ArgumentError, "TCX parse error: #{List.to_string(reason)}"

            {:error, reason} ->
              raise ArgumentError, "TCX parse error: #{inspect(reason)}"
          end
        after
          Process.delete(checkpoint)
        end
      end)
    end)
  end
end
