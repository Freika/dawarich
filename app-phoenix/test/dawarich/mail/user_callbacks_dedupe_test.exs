defmodule Dawarich.Mail.UserCallbacksDedupeTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Mail.{UserCallbacks, WelcomeWorker}

  test "the dedupe key survives a worker module that is not loaded when the job is published" do
    [[user]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('dedupe@example.test','{}',now(),now()) RETURNING id"
      )

    Ownership.put!(ScratchRepo, "command:mail.user.welcome", :oban)
    test = self()
    handler = {__MODULE__, test}

    :ok =
      :telemetry.attach(
        handler,
        ScratchRepo.config()[:telemetry_prefix] ++ [:query],
        fn _, _, _, _ ->
          if self() == test and Process.put(handler, true) == nil do
            :code.purge(WelcomeWorker)
            :code.delete(WelcomeWorker)
          end
        end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(handler)
      Code.ensure_loaded!(WelcomeWorker)
    end)

    event = Ecto.UUID.generate()
    payload = %{"user_id" => user, "locale" => "en"}
    assert UserCallbacks.enqueue(ScratchRepo, "welcome", payload, event_id: event) == :ok
    assert Process.get(handler)

    assert rows("SELECT dedupe_key FROM job_outbox WHERE event_id=$1", [Ecto.UUID.dump!(event)]) ==
             [["welcome:#{user}"]]
  end
end
