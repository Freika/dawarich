defmodule Dawarich.ReleaseDispatcherTest do
  use ExUnit.Case, async: true

  alias Dawarich.CLI

  @root Path.expand("../../..", __DIR__)
  @dispatcher Path.join(@root, "app-phoenix/rel/env.sh.eex")

  test "release dispatcher recognizes every Docker and Cloud rollout command" do
    dir = Path.join(System.tmp_dir!(), "release-dispatcher-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "bin"))
    on_exit(fn -> File.rm_rf!(dir) end)
    launcher = Path.join(dir, "bin/dawarich")
    File.write!(launcher, "#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
    File.chmod!(launcher, 0o700)

    files =
      Path.wildcard(Path.join(@root, "docker/**/*"))
      |> Enum.filter(&File.regular?/1)
      |> Kernel.++([Path.join(@root, "docs/phoenix/l1-cloud-rollout.md")])

    invocations =
      for file <- files,
          [_, command] <-
            Regex.scan(~r/(?<![\w\/.\-])dawarich[ \t]+["']?([a-z][\w:\-]*)/, File.read!(file)),
          do: {Path.relative_to(file, @root), command}

    assert Enum.any?(invocations, &(elem(&1, 1) == "seeds"))
    assert Enum.any?(invocations, &(elem(&1, 1) == "eval"))
    assert Enum.any?(invocations, &(elem(&1, 1) == "start"))

    cli_commands = CLI.commands() |> Enum.map(&hd/1) |> Enum.uniq()

    for {file, command} <- invocations ++ Enum.map(cli_commands, &{"CLI.commands()", &1}) do
      {output, status} =
        System.cmd("sh", [@dispatcher, command, "argument with spaces"],
          env: [
            {"RELEASE_ROOT", dir},
            {"RELEASE_NAME", "dawarich"},
            {"DAWARICH_COOKIE_FILE", Path.join(dir, "cookie")}
          ],
          stderr_to_stdout: true
        )

      assert status == 0, "#{file}: #{command} failed: #{output}"

      if command in cli_commands do
        assert output == "eval\nDawarich.CLI.main()\n#{command}\nargument with spaces\n",
               "#{file}: dawarich #{command} must dispatch through the native CLI"
      else
        assert command in ~w(eval start), "#{file}: unknown release command #{command}"
        assert output == "", "#{file}: #{command} must retain the standard release handler"
      end
    end

    assert CLI.resolve(["migrate"]) == {:ok, {Dawarich.CLI.Migrate, :migrate}, []}
    assert CLI.resolve(["seeds"]) == {:ok, {Dawarich.CLI.Seeds, :seeds}, []}
    assert CLI.resolve(["db:seed"]) == CLI.resolve(["seeds"])
  end
end
