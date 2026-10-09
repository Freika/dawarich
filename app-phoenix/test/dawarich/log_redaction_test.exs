defmodule Dawarich.LogRedactionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @password "synthetic-crash-password-7"
  @key "synthetic-crash-api-key-7"

  defmodule Crasher do
    use GenServer

    def init(state), do: {:ok, state}

    def handle_info(%Phoenix.Socket.Message{payload: %{"value" => value}}, state),
      do: {:noreply, handle(value, state)}

    defp handle(%{"mode" => "clause"} = params, _state), do: clause(params)

    defp handle(_value, _state), do: raise("event handler failed")

    defp clause(%{"never" => true}), do: :ok
  end

  defp crash_with(value) do
    capture_log(fn ->
      {:ok, pid} =
        GenServer.start(Crasher, %{
          socket: %{assigns: %{form: %{"user" => %{"password" => @password}}}}
        })

      ref = Process.monitor(pid)

      send(pid, %Phoenix.Socket.Message{
        topic: "lv:phx-test",
        event: "event",
        payload: %{"event" => "create_user", "type" => "form", "value" => value}
      })

      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
      Logger.flush()
    end)
  end

  test "crash report never contains submitted secrets" do
    log =
      crash_with(
        "user%5Bemail%5D=a%40example.invalid&user%5Bpassword%5D=#{@password}&settings%5Bimmich_api_key%5D=#{@key}"
      )

    assert log =~ "event handler failed"
    refute log =~ @password
    refute log =~ @key
  end

  test "function clause arguments in a crash report are redacted" do
    log =
      crash_with(%{"mode" => "clause", "user" => %{"password" => @password}, "api_key" => @key})

    assert log =~ "FunctionClauseError"
    refute log =~ @password
    refute log =~ @key
  end
end
