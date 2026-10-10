defmodule Dawarich.A12f3bM06Test do
  use Dawarich.JobsCase
  alias Dawarich.Mail.{AccountDestroyConfirmationWorker, OauthAccountLinkWorker, UserCallbacks}
  alias Dawarich.Jobs.Ownership

  setup do
    previous = Map.take(System.get_env(), ~w(DOMAIN RAILS_ENV))
    System.put_env(%{"DOMAIN" => "mail.example.test", "RAILS_ENV" => "production"})

    on_exit(fn ->
      Enum.each(~w(DOMAIN RAILS_ENV), &System.delete_env/1)
      System.put_env(previous)
    end)

    Ownership.put!(ScratchRepo, "command:mail.user.oauth_account_link", :oban)
    Ownership.put!(ScratchRepo, "command:mail.user.account_destroy_confirmation", :oban)
    :ok
  end

  defp user! do
    [[id]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('link@example.test','{\"locale\":\"de\"}',now(),now()) RETURNING id"
      )

    id
  end

  defp queued!(action, id) do
    payload =
      Jason.encode!(%{"exp" => System.os_time(:second) + 1800})
      |> Base.url_encode64(padding: false)

    url = "https://account.example.test/confirm?token=synthetic.#{payload}.signature"

    assert {:ok, :ok} =
             UserCallbacks.link(ScratchRepo, action, id, url,
               provider_label: "Google",
               locale: "fr"
             )

    [[event, body]] =
      rows("SELECT event_id,payload FROM public.job_outbox WHERE command_type=$1", [
        "mail.user." <> action
      ])

    worker =
      if action == "oauth_account_link",
        do: OauthAccountLinkWorker,
        else: AccountDestroyConfirmationWorker

    assert {:ok, args} = worker.args_from_command(1, body)
    {worker, Map.put(args, "event_id", Ecto.UUID.cast!(event)), url}
  end

  @tag a12f3b_case: "M06a"
  test "OAuth link and destroy confirmation mails preserve retained token URLs" do
    id = user!()

    for action <- ["oauth_account_link", "account_destroy_confirmation"] do
      {worker, args, url} = queued!(action, id)
      assert worker.perform(%Oban.Job{args: args}) == :ok
      assert_received {:mail, mail}
      assert String.contains?(mail.text, url)
      assert String.contains?(mail.html, url)
      assert mail.to == "link@example.test"
      if action == "oauth_account_link", do: assert(mail.subject =~ "Google")
      assert worker.perform(%Oban.Job{args: Map.put(args, "link_expires_at", 0)}) == :ok
      refute_received {:mail, _}
    end
  end

  @tag a12f3b_case: "M06b"
  test "confirmation mail failure cannot complete account destruction" do
    id = user!()
    {worker, args, _} = queued!("account_destroy_confirmation", id)
    Process.put(:transport_result, {:error, :rejected})
    assert worker.perform(%Oban.Job{args: args}) == {:error, :rejected}
    assert_received {:mail, _}
    assert rows("SELECT deleted_at FROM users WHERE id=$1", [id]) == [[nil]]
    assert rows("SELECT delivered_at FROM phoenix.delivery_claims") == [[nil]]
    Process.delete(:transport_result)
    assert worker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, _}
    assert rows("SELECT deleted_at FROM users WHERE id=$1", [id]) == [[nil]]
  end

  test "L1 distinct account link tokens retain independent mail intents and replay receipts" do
    id = user!()

    for action <- ["oauth_account_link", "account_destroy_confirmation"] do
      payload =
        Base.url_encode64(Jason.encode!(%{"exp" => System.os_time(:second) + 1800}),
          padding: false
        )

      first = "https://account.example.test/confirm?token=first.#{payload}.signature"
      second = "https://account.example.test/confirm?token=second.#{payload}.signature"
      opts = [provider_label: "Google", locale: "fr"]
      assert {:ok, :ok} = UserCallbacks.link(ScratchRepo, action, id, first, opts)
      assert {:ok, :ok} = UserCallbacks.link(ScratchRepo, action, id, second, opts)
      assert {:ok, :ok} = UserCallbacks.link(ScratchRepo, action, id, first, opts)
      command = "mail.user." <> action
      assert rows("SELECT count(*) FROM job_outbox WHERE command_type=$1", [command]) == [[2]]

      [[event]] =
        rows(
          "SELECT event_id FROM job_outbox WHERE command_type=$1 AND payload->>'link_url'=$2",
          [command, first]
        )

      Dawarich.Jobs.Processed.mark!(ScratchRepo, Ecto.UUID.load!(event), command)
      rows("DELETE FROM job_outbox WHERE event_id=$1", [event])
      assert {:ok, :ok} = UserCallbacks.link(ScratchRepo, action, id, first, opts)
      assert rows("SELECT count(*) FROM job_outbox WHERE command_type=$1", [command]) == [[1]]
    end
  end
end
