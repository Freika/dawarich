defmodule Dawarich.A12f3bM03Test do
  use Dawarich.JobsCase
  alias Dawarich.Mail.{DeviseCallbacks, DeviseNotificationWorker}
  @env %{"SELF_HOSTED" => "false", "RAILS_ENV" => "production"}

  setup do
    start_oban(:mail_credentials)
    :ok
  end

  defp user!(email) do
    [[id]] =
      rows(
        "INSERT INTO users(email,encrypted_password,settings,created_at,updated_at) VALUES($1,'old-hash',$2,now(),now()) RETURNING id",
        [email, %{"locale" => "de"}]
      )

    id
  end

  @tag a12f3b_case: "M03a"
  test "Cloud email and password changes issue source native notification mails" do
    id = user!("old@example.test")
    opts = [env: @env, oban: :mail_credentials, locale: "fr"]

    assert {:ok, _} =
             DeviseCallbacks.update(
               ScratchRepo,
               id,
               %{email: "new@example.test", encrypted_password: "new-hash"},
               opts
             )

    jobs = rows("SELECT args FROM oban.oban_jobs ORDER BY id") |> List.flatten()
    assert Enum.map(jobs, & &1["kind"]) == ["email_changed", "password_change"]

    for args <- jobs do
      assert DeviseNotificationWorker.perform(%Oban.Job{args: args}) == :ok
      assert_received {:mail, mail}

      assert mail.to ==
               if(args["kind"] == "email_changed",
                 do: "old@example.test",
                 else: "new@example.test"
               )

      assert mail.format == :html_only
      assert mail.html =~ "new@example.test"
      assert {:ok, mail.subject} == Dawarich.I18n.t("de", "devise.mailer.#{args["kind"]}.subject")
    end

    assert {:ok, _} = DeviseCallbacks.update(ScratchRepo, id, %{email: "new@example.test"}, opts)
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[2]]

    assert {:ok, _} =
             DeviseCallbacks.update(
               ScratchRepo,
               id,
               %{email: "selfhost@example.test"},
               Keyword.put(opts, :env, %{"SELF_HOSTED" => "true", "RAILS_ENV" => "production"})
             )

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[2]]
    {:ok, out} = StringIO.open("")
    {:ok, err} = StringIO.open("")
    ctx = %{repo: ScratchRepo, env: @env, oban: :mail_credentials, out: out, err: err}
    assert Dawarich.CLI.Users.email(["selfhost@example.test", "cli@example.test"], ctx) == 0
    [[args]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id DESC LIMIT 1")
    assert args["recipient"] == "selfhost@example.test"
    assert args["resource_email"] == "cli@example.test"
  end

  @tag a12f3b_case: "M03b"
  test "failed credential transaction produces no change notification" do
    id = user!("unchanged@example.test")
    user!("taken@example.test")
    opts = [env: @env, oban: :mail_credentials]

    assert_raise Postgrex.Error, fn ->
      DeviseCallbacks.update(ScratchRepo, id, %{email: "taken@example.test"}, opts)
    end

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert rows("SELECT email FROM users WHERE id=$1", [id]) == [["unchanged@example.test"]]

    assert {:error, :cancelled} =
             ScratchRepo.transaction(fn ->
               assert {:ok, _} =
                        DeviseCallbacks.update(
                          ScratchRepo,
                          id,
                          %{email: "rolledback@example.test"},
                          opts
                        )

               ScratchRepo.rollback(:cancelled)
             end)

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    Process.put(:transport_result, {:error, :rejected})

    assert {:error, {:delivery, :rejected}} =
             DeviseCallbacks.update(ScratchRepo, id, %{email: "committed@example.test"}, opts)

    assert rows("SELECT email FROM users WHERE id=$1", [id]) == [["committed@example.test"]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    assert rows("SELECT delivered_at FROM phoenix.delivery_claims") == [[nil]]
    assert_received {:mail, _}
  end
end
