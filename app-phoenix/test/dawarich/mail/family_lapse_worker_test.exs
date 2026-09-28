defmodule Dawarich.Mail.FamilyLapseWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Mail.FamilyLapseWorker

  defp user!(email, settings) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, created_at, updated_at) VALUES ($1, $2, now(), now()) RETURNING id",
        [email, settings]
      )

    id
  end

  defp setup_family!(member_settings \\ %{"locale" => "de"}) do
    owner = user!("owner@example.test", %{})
    member = user!("member@example.test", member_settings)

    [[family_id]] =
      rows(
        "INSERT INTO families (name, creator_id, created_at, updated_at) VALUES ('Home Crew', $1, now(), now()) RETURNING id",
        [owner]
      )

    {member, family_id}
  end

  defp args(member, family_id),
    do: %{
      "event_id" => Ecto.UUID.generate(),
      "user_id" => member,
      "family_id" => family_id,
      "locale" => "en",
      "lapse_at" => "none"
    }

  defp family_settings(user_id) do
    [[settings]] = rows("SELECT settings->'family' FROM users WHERE id = $1", [user_id])
    settings
  end

  test "lapse: marks under the lock and sends once" do
    {member, family_id} = setup_family!()
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          rows("SELECT 1 FROM users WHERE id = $1 FOR UPDATE", [member])
          send(parent, :holding)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :holding

    error =
      assert_raise Postgrex.Error, fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("SET LOCAL lock_timeout = '200ms'")
          perform_job(FamilyLapseWorker, args(member, family_id))
        end)
      end

    assert error.postgres.code == :lock_not_available
    refute_received {:mail, _}
    send(holder.pid, :release)
    Task.await(holder)

    assert perform_job(FamilyLapseWorker, args(member, family_id)) == :ok
    assert_received {:mail, %{to: "member@example.test"} = mail}

    assert {:ok, mail.subject} ==
             Dawarich.I18n.t("de", "mailers.family.plan_lapsed.subject", %{
               "family" => "Home Crew"
             })

    assert mail.text =~ "owner@example.test"
    assert %{"plan_lapse_notified_at" => marked_at} = family_settings(member)
    assert {:ok, _, 0} = DateTime.from_iso8601(marked_at)

    assert perform_job(FamilyLapseWorker, args(member, family_id)) == :ok
    refute_received {:mail, _}
  end

  test "lapse: a marked user sends nothing" do
    marked = %{"family" => %{"plan_lapse_notified_at" => "2026-01-01T00:00:00+01:00"}}
    {member, family_id} = setup_family!(marked)

    assert perform_job(FamilyLapseWorker, args(member, family_id)) == :ok
    refute_received {:mail, _}
    assert family_settings(member) == marked["family"]
  end

  test "lapse: an SMTP error clears the mark" do
    {member, family_id} = setup_family!(%{"family" => %{"keep" => true}})
    Process.put(:transport_result, {:error, {:temporary_failure, "451"}})

    assert perform_job(FamilyLapseWorker, args(member, family_id)) ==
             {:error, {:temporary_failure, "451"}}

    assert_received {:mail, _}
    assert family_settings(member) == %{"keep" => true}
  end

  test "lapse: a raise clears and reraises" do
    {member, family_id} = setup_family!()
    Process.put(:crash_after_send, true)

    assert_raise RuntimeError, fn -> perform_job(FamilyLapseWorker, args(member, family_id)) end
    assert_received {:mail, _}
    assert family_settings(member) == %{}
  end

  test "lapse: a kill during the SMTP send leaves the notice to the retry of that command only" do
    {member, family_id} = setup_family!()
    job = args(member, family_id)
    parent = self()

    sender =
      spawn(fn ->
        Process.put(:hang_in_transport, parent)
        perform_job(FamilyLapseWorker, job)
      end)

    assert_receive :in_transport
    Process.exit(sender, :kill)
    assert %{"plan_lapse_notified_at" => _} = family_settings(member)

    assert perform_job(FamilyLapseWorker, %{job | "event_id" => Ecto.UUID.generate()}) == :ok
    refute_received {:mail, _}

    assert perform_job(FamilyLapseWorker, job) == :ok
    assert_received {:mail, %{to: "member@example.test"}}

    assert perform_job(FamilyLapseWorker, job) == :ok
    refute_received {:mail, _}
  end

  test "a missing member or family is a silent no-op" do
    {member, family_id} = setup_family!()
    rows("UPDATE users SET deleted_at = now() WHERE id = $1", [member])

    assert perform_job(FamilyLapseWorker, args(member, family_id)) == :ok
    assert perform_job(FamilyLapseWorker, args(member + 1_000, family_id)) == :ok
    assert perform_job(FamilyLapseWorker, args(member, family_id + 1_000)) == :ok
    refute_received {:mail, _}
  end
end
