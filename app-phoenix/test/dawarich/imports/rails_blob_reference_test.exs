defmodule Dawarich.Imports.RailsBlobReferenceTest do
  use ExUnit.Case, async: true
  alias Dawarich.Imports.RailsBlobReference

  test "existing Rails signed blob references retain purpose-bound compatibility" do
    token = Dawarich.RailsMessages.blob_id(331)
    assert {:ok, 331} = RailsBlobReference.verify(token)
    assert {:error, :invalid_token} = RailsBlobReference.verify(token <> "modified")
    assert {:error, :invalid_token} = RailsBlobReference.verify("unknown")

    assert {:error, :invalid_token} =
             RailsBlobReference.verify(Dawarich.RailsMessages.blob_id(-1))
  end
end
