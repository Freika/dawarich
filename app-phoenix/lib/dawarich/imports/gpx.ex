defmodule Dawarich.Imports.Gpx do
  @moduledoc false
  alias Dawarich.Imports.{GpxHandler, XmlInput}

  def reduce(path, import, acc, fun) do
    File.open!(path, [:read, :binary], fn io ->
      checkpoint = make_ref()
      input = XmlInput.new(io) |> Map.put(:checkpoint, checkpoint)

      try do
        options = [
          :disallow_entities,
          external_entities: :none,
          event_fun: &GpxHandler.event/3,
          event_state: GpxHandler.new(import, acc, fun),
          continuation_fun: &XmlInput.next/1,
          continuation_state: input
        ]

        case :xmerl_sax_parser.stream(<<>>, options) do
          {:ok, state, rest} ->
            XmlInput.finish(rest, Process.get(checkpoint, input))
            {state.acc, state.counts}

          {:gpx_callback_error, _, {kind, reason, stack}, _, _} ->
            :erlang.raise(kind, reason, stack)

          {:fatal_error, error} when is_exception(error) ->
            raise error

          {:fatal_error, _, reason, _, _} ->
            raise ArgumentError, "GPX parse error: #{List.to_string(reason)}"

          {:error, reason} ->
            raise ArgumentError, "GPX parse error: #{inspect(reason)}"
        end
      after
        Process.delete(checkpoint)
      end
    end)
  end
end
