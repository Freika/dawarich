defmodule Dawarich.RawData.ArchiveFormatTest do
  use ExUnit.Case, async: true

  alias Dawarich.RawData.ArchiveFormat
  alias Dawarich.Wave6Fixtures

  defp fixture, do: Wave6Fixtures.load!("raw_archive")

  defp fixture_key(fixture),
    do: ArchiveFormat.key(%{"ARCHIVE_ENCRYPTION_KEY" => fixture["secret"]})

  defp tamper_tag(message) do
    [ciphertext, iv, tag] = String.split(message, "--")
    <<first, rest::binary>> = Base.decode64!(tag)
    Enum.join([ciphertext, iv, Base.encode64(<<Bitwise.bxor(first, 1), rest::binary>>)], "--")
  end

  test "derives Rails' key from ARCHIVE_ENCRYPTION_KEY" do
    fixture = fixture()
    other = ArchiveFormat.key(%{"ARCHIVE_ENCRYPTION_KEY" => fixture["secret"] <> "-other"})

    assert {:ok, _gzip} =
             ArchiveFormat.decode(fixture["message"], fixture["metadata"], fixture_key(fixture))

    assert ArchiveFormat.decode(fixture["message"], fixture["metadata"], other) ==
             {:error, :decrypt_failed}
  end

  test "falls back to the Rails secret" do
    secret = Application.fetch_env!(:dawarich, :rails_secret)

    assert ArchiveFormat.key(%{}) ==
             :crypto.pbkdf2_hmac(:sha256, secret, "points_raw_data_archive", 65_536, 32)
  end

  test "encrypts byte-identically to MessageEncryptor for Rails' IV" do
    fixture = fixture()
    gzip = Base.decode64!(fixture["gzip_b64"])
    iv = Base.decode64!(fixture["iv_b64"])

    assert ArchiveFormat.encrypt(gzip, fixture_key(fixture), iv) == fixture["message"]
  end

  test "decrypts a Rails archive to its lines" do
    fixture = fixture()

    assert {:ok, gzip} =
             ArchiveFormat.decode(fixture["message"], fixture["metadata"], fixture_key(fixture))

    assert ArchiveFormat.lines(gzip) == fixture["lines"]
  end

  test "a tampered tag fails" do
    key = :crypto.strong_rand_bytes(32)
    message = ArchiveFormat.encrypt(ArchiveFormat.build(["a"]), key)

    assert ArchiveFormat.decode(message, %{"format_version" => 2}, key) |> elem(0) == :ok

    assert ArchiveFormat.decode(tamper_tag(message), %{"format_version" => 2}, key) ==
             {:error, :decrypt_failed}
  end

  test "a Marshal payload is reported" do
    key = :crypto.strong_rand_bytes(32)
    iv = :crypto.strong_rand_bytes(12)
    plaintext = <<4, 8, 73, 34, 6, 97, 6, 58, 6, 69, 84>>
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, "", true)
    message = Enum.map_join([ciphertext, iv, tag], "--", &Base.encode64/1)

    assert ArchiveFormat.decode(message, %{"format_version" => 2}, key) ==
             {:error, :marshal_payload}
  end

  test "format_version below 2 passes plain gzip; \"2\" as a string decrypts" do
    key = :crypto.strong_rand_bytes(32)
    gzip = ArchiveFormat.build(["{\"id\":1}"])
    message = ArchiveFormat.encrypt(gzip, key)

    assert ArchiveFormat.decode(gzip, %{"format_version" => 1}, key) == {:ok, gzip}
    assert ArchiveFormat.decode(gzip, %{}, key) == {:ok, gzip}
    assert ArchiveFormat.decode(message, %{"format_version" => "2"}, key) == {:ok, gzip}
    assert ArchiveFormat.decode(message, %{"format_version" => 2.0}, key) == {:ok, gzip}
  end

  test "format_version follows Ruby's String#to_i" do
    key = :crypto.strong_rand_bytes(32)
    gzip = ArchiveFormat.build(["{\"id\":1}"])
    message = ArchiveFormat.encrypt(gzip, key)

    for version <- ["1_0", "2x", " 3", 2.9] do
      assert ArchiveFormat.decode(message, %{"format_version" => version}, key) == {:ok, gzip},
             inspect(version)
    end

    for version <- ["", "x2", "1", nil] do
      assert ArchiveFormat.decode(gzip, %{"format_version" => version}, key) == {:ok, gzip},
             inspect(version)
    end
  end

  test "a truncated tag or an IV other than 12 bytes fails" do
    key = :crypto.strong_rand_bytes(32)
    plaintext = Jason.encode!(Base.encode64(ArchiveFormat.build(["a"])))

    seal = fn iv ->
      {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, "", true)
      {ciphertext, iv, tag}
    end

    join = fn parts -> Enum.map_join(Tuple.to_list(parts), "--", &Base.encode64/1) end
    {ciphertext, iv, tag} = seal.(:crypto.strong_rand_bytes(12))
    truncated = join.({ciphertext, iv, binary_part(tag, 0, 8)})

    assert ArchiveFormat.decode(truncated, %{"format_version" => 2}, key) ==
             {:error, :decrypt_failed}

    for size <- [11, 13] do
      assert ArchiveFormat.decode(
               join.(seal.(:crypto.strong_rand_bytes(size))),
               %{"format_version" => 2},
               key
             ) ==
               {:error, :decrypt_failed},
             "IV of #{size} bytes"
    end
  end

  test "an interior empty line survives so the parser fails like Ruby" do
    assert ArchiveFormat.lines(ArchiveFormat.build(["a", "", "b"])) == ["a", "", "b"]
  end

  test "ids checksum sorts numerically" do
    sorted = :sha256 |> :crypto.hash("9,10,100,1001") |> Base.encode16(case: :lower)

    assert ArchiveFormat.ids_checksum([1001, 100, 10, 9]) == sorted
    assert ArchiveFormat.ids_checksum([1001, 100, 10, 9]) == fixture()["point_ids_checksum"]
  end
end
