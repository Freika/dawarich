defmodule Dawarich.Imports.GooglePhoneStreamTest do
  use ExUnit.Case, async: true
  alias Dawarich.Imports.JsonStream
  @root Path.expand("../../fixtures/imports/google_phone", __DIR__)
  @oracle Jason.decode!(File.read!(Path.join(@root, "stream-oracle.json")))

  for row <- @oracle["cases"], phase <- ["validate", "stream"] do
    @row row
    @phase phase
    test "actual Phone Oj phase #{@phase}: #{@row["name"]}" do
      expected = @row["phases"][@phase]
      path = Path.join(@root, @row["name"] <> ".json")
      Process.put(:phone_events, [])

      result =
        try do
          JsonStream.reduce(path, nil, &event/2, fn _ -> true end,
            mode: if(@phase == "validate", do: :phone_validate, else: :phone_saj)
          )

          :ok
        rescue
          e in [JsonStream.Error, ArgumentError] -> {:error, e}
        end

      if expected["class"] do
        assert match?({:error, _}, result)

        if expected["class"] == "ArgumentError",
          do:
            assert(match?({:error, %ArgumentError{message: "string contains null byte"}}, result))
      else
        assert result == :ok
      end

      if @phase == "stream",
        do: assert(Enum.reverse(Process.get(:phone_events)) == expected["events"])

      Process.delete(:phone_events)
    end
  end

  defp event({:start, kind, [], _}, _), do: kind

  defp event({:value, [index], value, _, _}, :array) when is_integer(index) do
    emit("raw_array", value)
    :array
  end

  defp event({:value, [index, key], value, _, _}, :object)
       when is_integer(index) and key in ["semanticSegments", "rawSignals"] do
    emit(if(key == "semanticSegments", do: "semantic_segment", else: "raw_signal"), value)
    :object
  end

  defp event({:value, ["userLocationProfile"], value, _, _}, :object) do
    if not is_list(value), do: emit("profile", value)
    :object
  end

  defp event(_, acc), do: acc

  defp emit(section, value),
    do: Process.put(:phone_events, [[section, plain(value)] | Process.get(:phone_events)])

  defp plain({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, plain(v)} end)

  defp plain(v) when v in [:infinity, :neg_infinity, :nan],
    do: %{"$float" => %{infinity: "Infinity", neg_infinity: "-Infinity", nan: "NaN"}[v]}

  defp plain(v) when is_list(v), do: Enum.map(v, &plain/1)
  defp plain(v), do: v
end
