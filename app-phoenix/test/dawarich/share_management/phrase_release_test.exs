defmodule Dawarich.ShareManagement.PhraseReleaseTest do
  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "phrases use the canonical wordlist without a Rails root or application cwd", %{
    tmp_dir: dir
  } do
    root = Application.fetch_env!(:dawarich, :rails_root)

    words =
      root
      |> Path.join("config/shared_link_wordlist.txt")
      |> File.read!()
      |> String.split("\n", trim: true)

    Application.delete_env(:dawarich, :rails_root)
    on_exit(fn -> Application.put_env(:dawarich, :rails_root, root) end)

    File.cd!(dir, fn ->
      for _ <- 1..20 do
        phrase = Dawarich.ShareManagement.Read.phrase() |> String.split("-")
        assert length(phrase) == 3
        assert Enum.all?(phrase, &(&1 in words))
      end
    end)
  end
end
