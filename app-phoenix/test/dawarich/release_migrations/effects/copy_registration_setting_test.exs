defmodule Dawarich.ReleaseMigrations.Effects.CopyRegistrationSettingTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.ReleaseMigrations.Effects.CopyRegistrationSetting, as: Copy

  @fixture Path.expand("../../../fixtures/auth/activation.json", __DIR__)

  test "copy decodes Rails true false and nil bytes and missing-key env default" do
    fixture = fixture()
    sources = [fixture["registration"] | Map.values(fixture["registration_legacy"])]

    for source <- sources, {name, value} <- [{"true", true}, {"false", false}, {"nil", nil}] do
      clear()
      assert {:ok, ^value} = copy(Base.decode64!(source[name]), true)
      assert rows("SELECT enabled FROM phoenix.registration_setting") == [[value]]
    end

    for default <- [true, false] do
      clear()
      assert {:ok, ^default} = copy(nil, default)
      assert rows("SELECT enabled FROM phoenix.registration_setting") == [[default]]
    end
  end

  test "unsupported registration bytes and Redis errors refuse copy" do
    for source <- Map.values(fixture()["registration_controls"]), bytes <- Map.values(source) do
      clear()
      assert {:error, :registration_copy_refused} = copy(Base.decode64!(bytes), true)
      assert rows("SELECT enabled FROM phoenix.registration_setting") == []
    end

    for bytes <- ["unknown", <<0, 17>>, <<0, 4, 8>>] do
      assert {:error, :registration_copy_refused} = copy(bytes, true)
      assert rows("SELECT enabled FROM phoenix.registration_setting") == []
    end

    assert {:error, :registration_copy_refused} =
             Copy.run(ScratchRepo, command: fn _ -> {:error, :disconnected} end)

    assert rows("SELECT enabled FROM phoenix.registration_setting") == []
  end

  test "versioned legacy registration boolean refuses copy without a singleton" do
    controls = fixture()["registration_controls"]

    for format <- ["marshal_7_0_uncompressed", "marshal_7_0_compressed"],
        name <- ["versioned_false", "compressed_versioned_false"] do
      assert {:error, :registration_copy_refused} =
               copy(Base.decode64!(controls[format][name]), true)

      assert rows("SELECT enabled FROM phoenix.registration_setting") == []
    end
  end

  test "existing registration row including nil skips Redis and wins on rerun" do
    for value <- [true, false, nil] do
      Dawarich.State.put_registration_enabled(ScratchRepo, value)
      command = fn _ -> flunk("existing singleton must not read Redis") end
      assert {:ok, ^value} = Copy.run(ScratchRepo, command: command)
      assert rows("SELECT enabled FROM phoenix.registration_setting") == [[value]]
    end
  end

  test "two real copy contenders keep one singleton and a committed admin value" do
    parent = self()
    source = Base.decode64!(fixture()["registration"]["true"])

    stale =
      Task.async(fn ->
        Copy.run(ScratchRepo,
          command: fn ["GET", "dawarich/registration_enabled"] ->
            send(parent, {:reading, self()})
            receive do: (:continue -> {:ok, source})
          end
        )
      end)

    on_exit(fn -> if Process.alive?(stale.pid), do: Task.shutdown(stale, :brutal_kill) end)
    stale_pid = stale.pid
    assert_receive {:reading, ^stale_pid}
    assert {:ok, true} = copy(source, false)

    admin =
      Dawarich.LockRace.hold(fn ->
        Dawarich.State.put_registration_enabled(ScratchRepo, false)
      end)

    send(stale.pid, :continue)
    assert :blocked = Dawarich.LockRace.settle(stale, "INSERT INTO phoenix.registration_setting%")
    assert :ok = Dawarich.LockRace.commit(admin)
    assert {:ok, false} = Task.await(stale)
    assert rows("SELECT enabled FROM phoenix.registration_setting") == [[false]]
  end

  test "failed copy can retry without a phantom completion" do
    assert {:error, :registration_copy_refused} = copy("unknown", true)
    assert rows("SELECT enabled FROM phoenix.registration_setting") == []
    assert {:ok, false} = copy(Base.decode64!(fixture()["registration"]["false"]), true)
    assert rows("SELECT enabled FROM phoenix.registration_setting") == [[false]]
  end

  test "copy closes its owned cache connection on success and refusal" do
    bytes = Base.decode64!(fixture()["registration"]["false"])

    for {source, expected} <- [
          {bytes, {:ok, false}},
          {"unknown", {:error, :registration_copy_refused}}
        ] do
      clear()

      assert Copy.run(ScratchRepo,
               cache_command: fn ["GET", "dawarich/registration_enabled"], conn ->
                 assert {:ok, "PONG"} = Redix.command(conn, ["PING"])
                 send(self(), {:connection, conn, Process.monitor(conn)})
                 {:ok, source}
               end
             ) == expected

      assert_received {:connection, conn, ref}
      on_exit(fn -> if Process.alive?(conn), do: Redix.stop(conn) end)
      assert_receive {:DOWN, ^ref, :process, ^conn, :normal}
    end
  end

  defp fixture, do: @fixture |> File.read!() |> Jason.decode!()
  defp clear, do: rows("DELETE FROM phoenix.registration_setting")

  defp copy(bytes, default) do
    Copy.run(ScratchRepo,
      env: %{"ALLOW_EMAIL_PASSWORD_REGISTRATION" => to_string(default)},
      command: fn ["GET", "dawarich/registration_enabled"] -> {:ok, bytes} end
    )
  end
end
