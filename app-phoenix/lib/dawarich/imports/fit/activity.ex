defmodule Dawarich.Imports.Fit.Activity do
  @moduledoc false
  alias Dawarich.Imports.Fit.Reader
  alias Dawarich.Imports.JsonStream.Spool

  def prepare(path, dir, now) do
    records = Path.join(dir, "records")
    sessions = Path.join(dir, "sessions")

    File.open!(records, [:write, :binary, :raw], fn record_io ->
      File.open!(sessions, [:write, :binary, :raw], fn session_io ->
        state = %{
          count: 0,
          lap: 0,
          session: 0,
          first_sport: nil,
          first_session: false,
          timestamp: 631_065_600,
          now: now,
          type: nil,
          activity: %{"timestamp" => now},
          devices: 0
        }

        state =
          Reader.reduce(
            path,
            state,
            fn entry, state ->
              consume(entry, state, record_io, session_io)
            end,
            activity: true
          )

        if state.type == 4, do: %{state | activity: state.activity} |> validate!(), else: nil
      end)
    end)
    |> case do
      nil -> nil
      state -> stream(records, sessions, state)
    end
  end

  defp consume(%{"number" => 0, "fields" => fields}, %{type: nil} = state, _, _),
    do: %{state | type: fields["type"]}

  defp consume(%{"number" => 20, "fields" => fields}, state, records, _) do
    fields = Map.put_new(fields, "timestamp", state.now)
    timestamp = fields["timestamp"]
    if is_nil(timestamp), do: raise(ArgumentError, "Record has no timestamp")

    if timestamp < state.timestamp,
      do: raise(ArgumentError, "Record has earlier timestamp than previous record")

    Spool.write!(records, fields)
    %{state | count: state.count + 1, timestamp: timestamp}
  end

  defp consume(%{"number" => 19}, state, _, _), do: %{state | lap: state.count}

  defp consume(%{"number" => 18, "fields" => fields}, state, _, sessions) do
    Spool.write!(sessions, {state.count, fields["sport"]})

    %{
      state
      | session: state.count,
        first_session: true,
        first_sport: if(state.first_session, do: state.first_sport, else: fields["sport"])
    }
  end

  defp consume(%{"number" => 34, "fields" => fields}, state, _, _),
    do: %{state | activity: Map.merge(state.activity, fields)}

  defp consume(%{"number" => 23}, state, _, _), do: %{state | devices: state.devices + 1}
  defp consume(_, state, _, _), do: state

  defp validate!(state) do
    if is_nil(state.activity["timestamp"]) or state.activity["timestamp"] < 631_152_000,
      do: raise(ArgumentError, "Activity has no valid timestamp")

    if is_nil(state.activity["total_timer_time"]),
      do: raise(ArgumentError, "Activity has no valid total_timer_time")

    state
  end

  defp stream(records, sessions, %{session: last}) when last > 0 do
    sports =
      Spool.stream(sessions, [:raw])
      |> Stream.transform(0, fn {last, sport}, first -> {[{last - first, sport}], last} end)
      |> Stream.flat_map(fn {count, sport} ->
        Stream.repeatedly(fn -> sport end) |> Stream.take(count)
      end)

    Stream.zip(Spool.stream(records, [:raw]), sports)
  end

  defp stream(records, _, state) do
    count = if state.lap > 0, do: state.lap, else: state.count
    records |> Spool.stream([:raw]) |> Stream.take(count) |> Stream.map(&{&1, state.first_sport})
  end
end
