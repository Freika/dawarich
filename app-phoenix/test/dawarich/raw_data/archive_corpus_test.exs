defmodule Dawarich.RawData.ArchiveCorpusTest do
  use ExUnit.Case, async: true

  alias Dawarich.RawData.ArchiveFormat
  alias Dawarich.Test.A12b

  @crypto A12b.fixture("crypto.json")
  @phrase "phoenix-a12b-archive-phrase-not-for-production"
  @rotated "phoenix-a12b-rotated-base-not-for-production"
  @v2 %{"format_version" => 2}

  defp env("absent"), do: %{}
  defp env("phrase"), do: %{"ARCHIVE_ENCRYPTION_KEY" => @phrase}
  defp env("empty"), do: %{"ARCHIVE_ENCRYPTION_KEY" => ""}
  defp base("secret"), do: A12b.secret()
  defp base("rotated"), do: @rotated
  defp key(env_label, base_label), do: ArchiveFormat.key(env(env_label), base(base_label))

  test "decrypts every message Rails wrote, under the environment it was written in" do
    for %{"env" => e, "base" => b, "message" => message, "gzip" => gzip} <-
          @crypto["archives"]["written"],
        do:
          assert(
            ArchiveFormat.decode(message, @v2, key(e, b)) == {:ok, Base.decode64!(gzip)},
            "#{e}+#{b}"
          )
  end

  test "reads exactly where Rails reads: absent, present and empty ARCHIVE_ENCRYPTION_KEY, rotated secret_key_base" do
    for %{"message" => message} = entry <- @crypto["archives"]["written"],
        {label, rails} <- entry["readable"] do
      [e, b] = String.split(label, "+")

      assert match?({:ok, _}, ArchiveFormat.decode(message, @v2, key(e, b))) == (rails == "ok"),
             label
    end
  end

  test "encrypts byte-for-byte what Rails encrypts, given Rails' IV" do
    for %{"env" => e, "base" => b, "message" => message, "gzip" => gzip} <-
          @crypto["archives"]["written"] do
      [_, iv, _] = String.split(message, "--")
      assert ArchiveFormat.encrypt(Base.decode64!(gzip), key(e, b), Base.decode64!(iv)) == message
    end
  end

  test "format_version follows Ruby's metadata&.dig('format_version').to_i" do
    [%{"message" => encrypted, "gzip" => gzip64} | _] = @crypto["archives"]["written"]
    gzip = Base.decode64!(gzip64)

    for %{"metadata" => metadata, "content" => kind, "outcome" => rails} <-
          @crypto["archives"]["versions"] do
      content = if kind == "plain", do: gzip, else: encrypted

      phoenix =
        case ArchiveFormat.decode(content, metadata, key("absent", "secret")) do
          {:ok, ^content} -> "plain"
          {:ok, ^gzip} -> "ok"
          {:error, _} -> "invalid"
        end

      assert phoenix == if(rails in ["invalid", "error"], do: "invalid", else: rails),
             inspect({metadata, kind})
    end
  end

  test "refuses every tampered message, including a truncated tag; the two Rails-only forms are ED-234" do
    rails_only = for %{"case" => c, "outcome" => "ok"} <- @crypto["archives"]["tampered"], do: c
    assert Enum.sort(rails_only) == ["expiry_envelope", "marshal_payload"]

    for %{"case" => c, "message" => message} <- @crypto["archives"]["tampered"],
        do:
          assert(
            match?({:error, _}, ArchiveFormat.decode(message, @v2, key("absent", "secret"))),
            c
          )

    [marshal] =
      for %{"case" => "marshal_payload", "message" => m} <- @crypto["archives"]["tampered"], do: m

    assert ArchiveFormat.decode(marshal, @v2, key("absent", "secret")) ==
             {:error, :marshal_payload}
  end

  test "an archive Rails' Archiver stored reads back to its lines, ids and checksums" do
    stored = @crypto["archives"]["stored"]
    assert ArchiveFormat.sha256(stored["message"]) == stored["metadata"]["content_checksum"]
    assert ArchiveFormat.ids_checksum(stored["ids"]) == stored["point_ids_checksum"]

    assert {:ok, gzip} =
             ArchiveFormat.decode(stored["message"], stored["metadata"], key("absent", "secret"))

    assert Enum.map(ArchiveFormat.lines(gzip), &Jason.decode!(&1)["id"]) == stored["ids"]
  end

  test "lines/1 reads Rails' JSONL exactly, and build/1 output reads back the same" do
    [%{"gzip" => gzip} | _] = @crypto["archives"]["written"]
    assert ArchiveFormat.lines(Base.decode64!(gzip)) == @crypto["archives"]["lines"]

    assert ArchiveFormat.lines(ArchiveFormat.build(@crypto["archives"]["lines"])) ==
             @crypto["archives"]["lines"]
  end

  test "property: encrypt/decode round-trips any gzip under any secret; a flip never yields other bytes" do
    A12b.seeded(fn n ->
      gzip = :rand.bytes(:rand.uniform(4097) - 1)
      secret = Enum.random(["", "x", @phrase, "phoenix-a12b-property-base-not-for-production"])
      key = ArchiveFormat.key(%{"ARCHIVE_ENCRYPTION_KEY" => secret})
      message = ArchiveFormat.encrypt(gzip, key)
      assert ArchiveFormat.decode(message, @v2, key) == {:ok, gzip}

      assert ArchiveFormat.decode(A12b.flip(message, rem(n * 13, byte_size(message))), @v2, key) in [
               {:ok, gzip},
               {:error, :decrypt_failed}
             ]

      assert ArchiveFormat.decode(binary_part(message, 0, byte_size(message) - 1), @v2, key) ==
               {:error, :decrypt_failed}
    end)
  end
end
