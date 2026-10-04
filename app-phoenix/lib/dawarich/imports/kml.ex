defmodule Dawarich.Imports.Kml do
  @moduledoc false
  alias Dawarich.Imports.{GpxProgress, NormalBatch, XmlInput, XmlAmpersands}
  alias Dawarich.Imports.JsonStream.Spool
  alias Dawarich.Imports.Kml.{Handler, Points}

  def call(path, import, context) do
    context = Map.put(context, :importer_name, "KML")

    Spool.with_directory(context, fn dir ->
      input = Path.join(dir, "input.xml")
      XmlAmpersands.copy(path, input)
      parse(input, dir)
      prepared = Path.join(dir, "prepared")

      File.open!(prepared, [:write, :binary, :raw], fn io ->
        for kind <- [:placemark, :track] do
          dir
          |> Path.join(Atom.to_string(kind))
          |> Spool.stream([:raw])
          |> Enum.each(fn file ->
            Points.reduce(file, kind, import, context, fn attrs -> Spool.write!(io, attrs) end)
          end)
        end
      end)

      {batch, progress} =
        prepared
        |> Spool.stream([:raw])
        |> Enum.reduce(
          {NormalBatch.new(import, context, :non_atomic), %{at: nil, index: nil}},
          fn attrs, {batch, progress} ->
            next = NormalBatch.push(batch, attrs)

            progress =
              if batch.size == 999,
                do:
                  GpxProgress.record(
                    import,
                    next.inserted - batch.inserted,
                    progress,
                    clock(context)
                  ),
                else: progress

            {next, progress}
          end
        )

      next = NormalBatch.finish(batch)

      if batch.size > 0,
        do: GpxProgress.record(import, next.inserted - batch.inserted, progress, clock(context))

      :ok
    end)
  end

  defp clock(context) do
    Map.update!(context, :now, fn
      %NaiveDateTime{} = now -> DateTime.from_naive!(now, "Etc/UTC")
      now -> now
    end)
  end

  defp parse(path, dir) do
    Handler.with_state(dir, fn state ->
      File.open!(path, [:read, :binary, :raw], fn io ->
        checkpoint = make_ref()
        input = XmlInput.new(io, streamed_text: true) |> Map.put(:checkpoint, checkpoint)

        try do
          options = [
            :disallow_entities,
            external_entities: :none,
            event_fun: &Handler.event/3,
            event_state: state,
            continuation_fun: &XmlInput.next/1,
            continuation_state: input
          ]

          case :xmerl_sax_parser.stream(<<>>, options) do
            {:ok, _, rest} ->
              XmlInput.finish(rest, Process.get(checkpoint, input))

            {:fatal_error, error} when is_exception(error) ->
              raise error

            {:fatal_error, _, reason, _, _} ->
              raise ArgumentError, "KML parse error: #{List.to_string(reason)}"

            {:error, reason} ->
              raise ArgumentError, "KML parse error: #{inspect(reason)}"
          end
        after
          Process.delete(checkpoint)
        end
      end)
    end)
  end
end
