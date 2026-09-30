defmodule Dawarich.EnhancedImport.Gpx do
  @moduledoc false

  alias Dawarich.EnhancedImport.GpxHandler

  @boms [
    <<0xEF, 0xBB, 0xBF>>,
    <<0xFE, 0xFF>>,
    <<0xFF, 0xFE>>,
    <<0, 0, 0xFE, 0xFF>>,
    <<0xFF, 0xFE, 0, 0>>
  ]

  def reduce(path, acc, fun) do
    File.open!(path, [:read, :binary], fn io ->
      prefix =
        case IO.binread(io, 256) do
          :eof -> ""
          data -> data
        end

      {:ok, _} = :file.position(io, offset(prefix))

      options = [
        :disallow_entities,
        event_fun: &GpxHandler.event/3,
        event_state: GpxHandler.new(acc, fun),
        continuation_fun: &continue/1,
        continuation_state: io,
        external_entities: :none
      ]

      case :xmerl_sax_parser.stream(<<>>, options) do
        {:ok, state, _rest} ->
          state.acc

        {:writer_error, _location, {exception, stacktrace}, _tags, _state} ->
          reraise exception, stacktrace

        {:fatal_error, exception} when is_exception(exception) ->
          raise exception

        {:fatal_error, _location, _reason, _tags, state} ->
          state.acc

        {:EXIT, _location, reason, _tags, _state} ->
          exit(reason)

        {:error, reason} ->
          raise ArgumentError, "GPX parser error: #{inspect(reason)}"
      end
    end)
  end

  defp offset(prefix) do
    cond do
      Enum.any?(@boms, &String.starts_with?(prefix, &1)) -> 0
      match = :binary.match(prefix, "<") -> elem(match, 0)
      true -> 0
    end
  end

  defp continue(io) do
    case IO.binread(io, 65_536) do
      :eof -> {<<>>, io}
      data -> {data, io}
    end
  end
end
