defmodule Dawarich.Build.Sprockets.Writer do
  @moduledoc false

  alias Jason.OrderedObject

  def etag(source),
    do: Base.encode16(:crypto.hash(:sha256, "1.0" <> :crypto.hash(:sha256, source)), case: :lower)

  def digest_path(logical, source) do
    case Regex.run(~r/\.\w+\z/, logical, return: :index) do
      [{start, _}] ->
        binary_part(logical, 0, start) <>
          "-" <>
          etag(source) <>
          binary_part(logical, start, byte_size(logical) - start)

      nil ->
        logical
    end
  end

  def now,
    do:
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> Calendar.strftime("%Y-%m-%dT%H:%M:%S+00:00")

  def write!(out, results, mtime) do
    dir = Path.join(out, "public/assets")

    for result <- results do
      target = Path.join(dir, result.digest_path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, result.source)
      if result.gzip, do: File.write!(target <> ".gz", gzip(result.source))
    end

    files =
      Enum.reduce(
        results,
        [],
        &List.keystore(&2, &1.digest_path, 0, {&1.digest_path, entry(&1, mtime)})
      )

    assets =
      Enum.reduce(results, [], &List.keystore(&2, &1.logical, 0, {&1.logical, &1.digest_path}))

    manifest = Path.join(out, "config/sprockets-manifest.json")
    File.mkdir_p!(Path.dirname(manifest))

    File.write!(
      manifest,
      Jason.encode_to_iodata!(%OrderedObject{
        values: [
          {"files", %OrderedObject{values: files}},
          {"assets", %OrderedObject{values: assets}}
        ]
      })
    )

    Map.new(assets)
  end

  def gzip(data) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, 9, :deflated, -15, 8, :default)
    body = :zlib.deflate(z, data, :finish)
    :ok = :zlib.deflateEnd(z)
    :zlib.close(z)

    IO.iodata_to_binary([
      <<0x1F, 0x8B, 8, 0, 0::32, 2, 3>>,
      body,
      <<:erlang.crc32(data)::little-32, byte_size(data)::little-32>>
    ])
  end

  defp entry(result, mtime) do
    digest = :crypto.hash(:sha256, result.source)

    %OrderedObject{
      values: [
        {"logical_path", result.logical},
        {"mtime", mtime},
        {"size", byte_size(result.source)},
        {"digest", Base.encode16(digest, case: :lower)},
        {"integrity", "sha256-" <> Base.encode64(digest)}
      ]
    }
  end
end
