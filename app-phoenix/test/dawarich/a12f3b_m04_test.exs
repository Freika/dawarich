defmodule Dawarich.A12f3bM04Test do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Mail.UserCallbacks
  @now ~U[2026-10-04 12:00:00.000000Z]
  @opts [env: %{"SELF_HOSTED" => "false"}, now: @now, locale: "fr"]

  setup do
    Ownership.put!(ScratchRepo, "command:mail.user.welcome", :oban)
    Ownership.put!(ScratchRepo, "command:users.explore_features_mail", :oban)
    :ok
  end

  defp user! do
    [[id]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('creation@example.test','{}',now(),now()) RETURNING id"
      )

    id
  end

  @tag a12f3b_case: "M04a"
  test "welcome and explore mail callbacks preserve delay locale and links" do
    id = user!()
    assert {:ok, :ok} = UserCallbacks.created(ScratchRepo, id, @opts)

    assert rows(
             "SELECT command_type,command_version,payload,scheduled_at FROM public.job_outbox ORDER BY scheduled_at"
           ) == [
             ["mail.user.welcome", 1, %{"user_id" => id, "locale" => "fr"}, @now],
             [
               "users.explore_features_mail",
               1,
               %{"user_id" => id, "locale" => "fr"},
               DateTime.add(@now, 172_800)
             ]
           ]

    assert {:ok, :ok} =
             UserCallbacks.created(
               ScratchRepo,
               id,
               Keyword.put(@opts, :env, %{"SELF_HOSTED" => "true"})
             )

    assert rows("SELECT count(*) FROM public.job_outbox") == [[2]]

    assert {:ok, :ok} =
             UserCallbacks.created(ScratchRepo, id, Keyword.put(@opts, :skip_auto_trial, true))

    assert rows("SELECT count(*) FROM public.job_outbox") == [[2]]
  end

  @tag a12f3b_case: "M04b"
  test "welcome callback rollback cannot enqueue either user mail" do
    assert {:error, :cancelled} =
             ScratchRepo.transaction(fn ->
               id = user!()
               assert {:ok, :ok} = UserCallbacks.created(ScratchRepo, id, @opts)
               ScratchRepo.rollback(:cancelled)
             end)

    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]
    id = user!()
    assert {:ok, :ok} = UserCallbacks.created(ScratchRepo, id, @opts)
    first = rows("SELECT event_id,scheduled_at FROM public.job_outbox ORDER BY command_type")

    assert {:ok, :ok} =
             UserCallbacks.created(
               ScratchRepo,
               id,
               Keyword.put(@opts, :now, DateTime.add(@now, 10))
             )

    assert rows("SELECT event_id,scheduled_at FROM public.job_outbox ORDER BY command_type") ==
             first
  end
end
