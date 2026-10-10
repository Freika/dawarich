defmodule Dawarich.Ingest.CastTest do
  use ExUnit.Case, async: true

  alias Dawarich.Ingest.{Cast, Unsupported}

  @units "test/fixtures/ingest/units.json" |> File.read!() |> Jason.decode!()

  test "every column cast agrees with ActiveModel's SerializeCastValue for owned inputs" do
    Code.ensure_loaded!(Cast)

    for %{"column" => column, "input" => input, "own" => own, "result" => ruby} <- @units["casts"] do
      phoenix =
        try do
          {:ok, Cast.column(String.to_existing_atom(column), input)}
        rescue
          Unsupported -> :unsupported
        end

      case {phoenix, ruby} do
        {:unsupported, %{"error" => _}} ->
          :ok

        {:unsupported, _} ->
          refute own, "#{column} must own #{inspect(input)}"

        {{:ok, value}, %{"ok" => expected}} ->
          assert same?(value, expected), "#{column} #{inspect(input)}"

        {{:ok, value}, error} ->
          flunk("#{column} #{inspect(input)}: Phoenix #{inspect(value)}, Rails #{inspect(error)}")
      end
    end
  end

  defp same?(%Decimal{} = value, expected), do: Decimal.equal?(value, Decimal.new(expected))
  defp same?(value, expected), do: value == expected
end
