defmodule Dawarich.Imports.BoundedLines do
  @moduledoc false
  alias Dawarich.Imports.ParserLimit
  @limit 1_048_576
  @chunk 16_384

  def stream(path) do
    Stream.resource(
      fn -> %{io: File.open!(path, [:read, :binary, :raw]), pending: "", parts: [], size: 0} end,
      &next/1,
      fn state -> File.close(state.io) end
    )
  end

  def validate!(path), do: Enum.each(stream(path), fn _ -> :ok end)

  defp next(%{pending: ""} = state) do
    case IO.binread(state.io, @chunk) do
      :eof ->
        if state.size == 0,
          do: {:halt, state},
          else: {[line(state)], %{state | parts: [], size: 0}}

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read", path: "import"

      bytes ->
        next(%{state | pending: bytes})
    end
  end

  defp next(state) do
    case :binary.match(state.pending, "\n") do
      :nomatch ->
        next(append(%{state | pending: ""}, state.pending))

      {index, 1} ->
        size = index + 1
        <<piece::binary-size(^size), rest::binary>> = state.pending
        state = append(%{state | pending: rest}, piece)
        {[line(state)], %{state | parts: [], size: 0}}
    end
  end

  defp append(state, piece) do
    size = state.size + byte_size(piece)
    if size > @limit, do: raise(ParserLimit, "Native physical line exceeds #{@limit} bytes")
    %{state | parts: [piece | state.parts], size: size}
  end

  defp line(state), do: state.parts |> Enum.reverse() |> IO.iodata_to_binary()
end
