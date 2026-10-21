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

  test "public unlock phrase is filtered in structured reports lazy iodata and query strings" do
    require Logger
    phrase = "synthetic-public-unlock-privacy-probe"

    log =
      capture_log(fn ->
        Logger.error(%{event: "public_unlock", phrase: phrase})
        Logger.error(fn -> ["public_unlock ", ["phrase=", phrase, "&attempt=1"]] end)
        Logger.error(fn -> JSON.encode_to_iodata!(%{event: "public_unlock", phrase: phrase}) end)
        Logger.flush()
      end)

    assert log =~ "public_unlock"
    assert log =~ "[FILTERED]"
    refute log =~ phrase

    assert Phoenix.Logger.filter_values(%{"phrase" => phrase, "attempt" => 1}) ==
             %{"phrase" => "[FILTERED]", "attempt" => 1}
  end

  test "legacy and canonical storage capabilities and private filenames are filtered" do
    for route <-
          ~w(blobs blobs/redirect blobs/proxy representations representations/redirect representations/proxy disk),
        prefix <- ["", "/mounted"] do
      path = "#{prefix}/rails/active_storage/#{route}/synthetic-signed-blob/private-file.gpx"
      filtered = Dawarich.LogRedaction.request_path(path <> "?download=1")
      refute filtered =~ "synthetic-signed-blob"
      refute filtered =~ "private-file.gpx"
      assert filtered =~ "?download=1"
    end

    assert Phoenix.Logger.filter_values(%{"signed_blob_id" => "synthetic-signed-blob"}) ==
             %{"signed_blob_id" => "[FILTERED]"}
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

  test "data event crashes redact phrases and attachment capabilities" do
    values = %{
      "phrase" => "synthetic-phrase-c1",
      "sgid" => "synthetic-sgid-c1",
      "upload_ref" => "synthetic-upload-c1",
      "capability" => "synthetic-capability-c1"
    }

    log = crash_with(Map.put(values, "mode", "clause"))
    assert log =~ "FunctionClauseError"
    for value <- Map.values(values), do: refute(log =~ value)
  end

  test "function clause arguments in a crash report are redacted" do
    log =
      crash_with(%{"mode" => "clause", "user" => %{"password" => @password}, "api_key" => @key})

    assert log =~ "FunctionClauseError"
    refute log =~ @password
    refute log =~ @key
  end

  test "a lazily built string message keeps its text and only drops secret query values" do
    require Logger

    log =
      capture_log(fn ->
        Logger.error(fn -> JSON.encode_to_iodata!(%{event: "job:stop", id: "synthetic-id-7"}) end)
        Logger.error(fn -> ["visit ", ["user=7&password=", @password]] end)
        Logger.error(fn -> JSON.encode_to_iodata!(%{source: "probe", api_key: @key}) end)
        Logger.flush()
      end)

    assert log =~ ~s("id":"synthetic-id-7")
    assert log =~ "visit user=7&password=[FILTERED]"
    assert log =~ ~s("source":"probe")
    refute log =~ @password
    refute log =~ @key
  end

  test "string scrubbing stays linear on adversarial input and drops whole quoted secrets" do
    adversarial = String.duplicate("token", 2000) <> " x=1"
    {micros, scrubbed} = :timer.tc(fn -> Dawarich.LogRedaction.scrub(adversarial) end)

    assert scrubbed == adversarial
    assert micros < 200_000

    assert Dawarich.LogRedaction.scrub("next=https://h.example/p?api_key=synthetic&x=1") ==
             "next=https://h.example/p?api_key=[FILTERED]&x=1"

    nested = String.duplicate("a=?", 6000) <> "token=1"
    {nested_micros, _} = :timer.tc(fn -> Dawarich.LogRedaction.scrub(nested) end)
    assert nested_micros < 200_000

    assert Dawarich.LogRedaction.scrub(~s(user=7 password="hunter two" done)) ==
             ~s(user=7 password=[FILTERED] done)

    assert Dawarich.LogRedaction.scrub("ctl\x01 password=hunter") == "ctl\x01 password=[FILTERED]"
  end

  test "single-quoted values and keyword or tuple pairs are redacted by key" do
    assert Dawarich.LogRedaction.scrub("password='hunter two' ok") == "password=[FILTERED] ok"

    assert Dawarich.LogRedaction.scrub([{:password, @password}, {:user, "u7"}]) ==
             [{:password, "[FILTERED]"}, {:user, "u7"}]

    assert Dawarich.LogRedaction.scrub({"api_key", @key}) == {"api_key", "[FILTERED]"}
  end

  test "a raise inside the filter replaces the message instead of removing the filter" do
    key = {Dawarich.LogRedaction, :words}
    previous = :persistent_term.get(key, nil)
    :persistent_term.put(key, :not_a_list)

    try do
      event = %{level: :info, meta: %{}, msg: {:report, %{user: "u7"}}}
      assert Dawarich.LogRedaction.filter(event, []).msg == {:string, "[FILTERED]"}
    after
      if previous, do: :persistent_term.put(key, previous), else: :persistent_term.erase(key)
    end
  end

  test "database error reports redact secret query details and crash metadata" do
    secret = "synthetic-query-error-capability"

    error = %Postgrex.Error{
      query: "SELECT id FROM family_invitations WHERE token=$1",
      message: "database error containing #{secret}",
      postgres: %{
        code: :invalid_text_representation,
        pg_code: "22P02",
        severity: "ERROR",
        message: "invalid input: #{secret}"
      }
    }

    event = %{
      level: :error,
      msg: {:report, %{reason: error}},
      meta: %{crash_reason: {error, []}, mfa: {DBConnection.Connection, :handle_event, 4}}
    }

    filtered = Dawarich.LogRedaction.filter(event, [])
    assert inspect(filtered) =~ "22P02"
    assert inspect(filtered) =~ "[FILTERED]"
    assert not String.contains?(inspect(filtered), secret)
  end

  test "DBConnection formatted Postgrex errors never carry secret query details" do
    require Logger
    secret = "synthetic-disconnect-capability"

    error = %Postgrex.Error{
      query: "SELECT id FROM family_invitations WHERE token=$1",
      postgres: %{
        code: :invalid_text_representation,
        pg_code: "22P02",
        severity: "ERROR",
        message: "invalid input: #{secret}"
      }
    }

    log =
      capture_log(fn ->
        Logger.error(fn ->
          ["Postgrex disconnected: " | Exception.format_banner(:error, error, [])]
        end)

        Logger.flush()
      end)

    assert log =~ "Postgrex.Error"
    assert not String.contains?(log, secret)
  end

  test "nil-query execution diagnostics preserve codes without capabilities in messages or crash metadata" do
    secret = "opaque-nil-query-invitation"

    error = %Postgrex.Error{
      query: nil,
      postgres: %{
        code: :unique_violation,
        pg_code: "23505",
        severity: "ERROR",
        message: "duplicate key value violates unique constraint",
        detail: "Key (token)=(#{secret}) already exists.",
        hint: secret
      }
    }

    event = %{
      level: :error,
      msg: {:report, %{execution_error: error}},
      meta: %{crash_reason: {error, []}}
    }

    filtered = Dawarich.LogRedaction.filter(event, [])
    assert not String.contains?(inspect(filtered), secret)
    assert inspect(filtered) =~ "23505"
    assert inspect(filtered) =~ "unique_violation"

    log =
      capture_log(fn ->
        require Logger
        Logger.error(%{execution_error: error}, crash_reason: {error, []})

        Logger.error(fn ->
          ["Postgrex disconnected: ", Exception.format_banner(:error, error, [])]
        end)

        Logger.flush()
      end)

    assert not String.contains?(log, secret)
    assert log =~ "Postgrex.Error"
  end
end
