defmodule Dawarich.Ingest.TimestampTest do
  use ExUnit.Case, async: true

  alias Dawarich.Ingest.{Timestamp, Unsupported}

  @units "test/fixtures/ingest/units.json" |> File.read!() |> Jason.decode!()

  defp points(input) do
    {:ok, Timestamp.points(input)}
  rescue
    Timestamp.Invalid -> :invalid
    Unsupported -> :unsupported
  end

  defp traccar(input) do
    {:ok, Timestamp.traccar(input)}
  rescue
    Unsupported -> :unsupported
  end

  test "Points::TimestampParser: owned inputs agree with Rails, the rest agree or go to Rails" do
    for %{"input" => input, "own" => own, "points" => ruby} <- @units["timestamps"] do
      expected =
        if ruby == %{"error" => "invalid_timestamp"}, do: :invalid, else: {:ok, ruby["ok"]}

      case points(input) do
        :unsupported ->
          refute own, "Phoenix must own #{inspect(input)}"

        result ->
          assert own, "Phoenix must not own #{inspect(input)}"
          assert result == expected, inspect(input)
      end
    end
  end

  test "Traccar's parse agrees with Rails or goes to Rails" do
    for %{"input" => input, "own" => own, "traccar" => %{"ok" => ruby}} <- @units["timestamps"] do
      case traccar(input) do
        :unsupported ->
          refute own, "Phoenix must own #{inspect(input)}"

        {:ok, value} ->
          assert own, "Phoenix must not own #{inspect(input)}"
          assert value == ruby, inspect(input)
      end
    end

    assert Timestamp.traccar("2024-01-01T12:00:00.000Z") == 1_704_110_400
    assert Timestamp.traccar(1_788_930_000_000) == 1_788_930_000
    assert Timestamp.traccar("2026-02-30T12:00:00Z") == nil
  end
end
