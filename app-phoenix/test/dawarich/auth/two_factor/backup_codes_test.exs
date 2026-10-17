defmodule Dawarich.Auth.TwoFactor.BackupCodesTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias Dawarich.Auth.TwoFactor.BackupCodes

  test "ten 24-character backup codes persist only compatible bcrypt hashes" do
    assert Code.ensure_loaded?(BackupCodes)
    entropy = fn count -> :binary.copy(<<171>>, count) end
    {:ok, codes, hashes} = BackupCodes.generate(entropy: entropy)
    assert length(codes) == 10
    assert length(hashes) == 10
    assert Enum.all?(codes, &(byte_size(&1) == 24 and Regex.match?(~r/\A[0-9a-f]{24}\z/, &1)))
    assert Enum.uniq(codes) == [Base.encode16(:binary.copy(<<171>>, 12), case: :lower)]

    assert Enum.all?(
             hashes,
             &(String.starts_with?(&1, "$2b$04$") and Bcrypt.verify_pass(hd(codes), &1))
           )

    assert MapSet.disjoint?(MapSet.new(codes), MapSet.new(hashes))
    assert {:ok, remaining} = BackupCodes.consume(hashes, hd(codes))
    assert remaining == tl(hashes)
    assert BackupCodes.consume(remaining, "not-a-code") == :invalid
    assert BackupCodes.consume(hashes, String.upcase(hd(codes))) == :invalid
    assert BackupCodes.consume(hashes, " #{hd(codes)} ") == :invalid
    assert BackupCodes.consume(nil, hd(codes)) == :invalid
    assert BackupCodes.consume([], hd(codes)) == :invalid
    assert BackupCodes.consume(hashes, nil) == :invalid
    assert BackupCodes.consume("legacy-string", hd(codes)) == {:handoff, :backup_state}
    assert BackupCodes.consume([7], hd(codes)) == {:handoff, :backup_state}
    assert BackupCodes.consume(["invalid-hash"], hd(codes)) == {:handoff, :backup_state}
    first = hd(hashes)
    assert {:ok, []} = BackupCodes.consume([first], hd(codes))
    assert BackupCodes.consume([], hd(codes)) == :invalid
    assert {:ok, [nil, ""]} = BackupCodes.consume([nil, first, first, ""], hd(codes))
    assert {:ok, [_ | _]} = BackupCodes.consume([first | tl(hashes)], hd(codes))
    assert {:ok, [_ | _]} = BackupCodes.consume([nil, "" | hashes], hd(codes))

    assert {:ok, pepper_codes, pepper_hashes} =
             BackupCodes.generate(entropy: entropy, pepper: "synthetic-pepper")

    assert {:ok, _} =
             BackupCodes.consume(pepper_hashes, hd(pepper_codes), pepper: "synthetic-pepper")

    assert BackupCodes.consume(pepper_hashes, hd(pepper_codes)) == :invalid
    log = capture_log(fn -> BackupCodes.generate(entropy: entropy) end)
    assert Enum.all?(codes ++ hashes, &(not String.contains?(log, &1)))
  end
end
