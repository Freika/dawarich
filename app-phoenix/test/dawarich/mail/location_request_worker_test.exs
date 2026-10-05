defmodule Dawarich.Mail.LocationRequestWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures
  alias Dawarich.Mail.{Delivery, LocationRequestWorker}

  @path Path.expand("../../fixtures/mail/residual/effects.json", __DIR__)
  @now ~N[2026-10-04 12:00:00]

  test "location mail uses target locale and source delivery eligibility" do
    previous = Map.take(System.get_env(), ~w(SMTP_FROM DOMAIN RAILS_ENV))

    System.put_env(%{
      "SMTP_FROM" => "Dawarich <residual@dawarich.test>",
      "DOMAIN" => "www.example.com",
      "RAILS_ENV" => "staging"
    })

    on_exit(fn ->
      Enum.each(~w(SMTP_FROM DOMAIN RAILS_ENV), &System.delete_env/1)
      System.put_env(previous)
    end)

    cases = @path |> File.read!() |> Jason.decode!() |> Map.fetch!("locations")

    assert Enum.map(cases, & &1["id"]) ==
             ~w(pending accepted expired missing_request missing_requester missing_target repeated cache_failure enqueue_failure missing_after_enqueue)

    for row <- Enum.reject(cases, &(&1["id"] in ~w(cache_failure enqueue_failure))) do
      reset!(ScratchRepo)
      load(row)
      payload = Map.take(row, ~w(request_id)) |> Map.put("user_id", row["requester_id"])
      assert {:ok, ^payload} = LocationRequestWorker.args_from_command(1, payload)

      assert LocationRequestWorker.args_from_command(2, payload) ==
               {:error, "unsupported_version"}

      assert LocationRequestWorker.args_from_command(1, Map.put(payload, "locale", "fr")) ==
               {:error, "invalid_payload"}

      args = Map.put(payload, "event_id", Ecto.UUID.generate())

      if row["id"] in ~w(missing_request missing_after_enqueue),
        do: rows("DELETE FROM public.family_location_requests WHERE id=$1", [row["request_id"]])

      if row["id"] == "missing_requester",
        do: rows("UPDATE public.users SET deleted_at=$2 WHERE id=$1", [row["requester_id"], @now])

      if row["id"] == "missing_target",
        do: rows("UPDATE public.users SET deleted_at=$2 WHERE id=$1", [row["target_id"], @now])

      result = LocationRequestWorker.perform(%Oban.Job{args: args})

      cond do
        row["id"] == "missing_target" ->
          assert match?({:error, _}, result)
          refute_received {:mail, _}

        row["id"] in ~w(missing_request missing_requester missing_after_enqueue) ->
          assert result == :ok
          refute_received {:mail, _}

        true ->
          assert result == :ok
          assert_received {:mail, message}
          expected = hd(row["smtp"]["attempts"])
          assert message.to == row["recipient"], "recipient differs: #{row["id"]}"
          assert message.locale == "de"
          assert message.subject == expected["subject"]

          if message.text != hd(expected["tree"]["parts"])["body"],
            do: flunk("text differs: #{row["id"]}")

          if message.html != List.last(expected["tree"]["parts"])["body"],
            do: flunk("HTML differs: #{row["id"]}")

          assert LocationRequestWorker.perform(%Oban.Job{args: args}) == :ok

          assert LocationRequestWorker.perform(%Oban.Job{
                   args: Map.put(args, "event_id", Ecto.UUID.generate())
                 }) == :ok

          refute_received {:mail, _}
      end
    end

    reset!(ScratchRepo)
    row = hd(cases)
    load(row)

    args = %{
      "request_id" => row["request_id"],
      "user_id" => row["requester_id"],
      "event_id" => Ecto.UUID.generate()
    }

    assert Delivery.claim(
             ScratchRepo,
             "mail.location_request",
             LocationRequestWorker.provider_key(args),
             Ecto.UUID.generate()
           ) == :send

    assert LocationRequestWorker.perform(%Oban.Job{args: args}) == {:snooze, 600}
    refute_received {:mail, _}
  end

  test "foreign requester request pairs create no SMTP attempt or delivery claim" do
    previous = Map.take(System.get_env(), ~w(SMTP_FROM DOMAIN RAILS_ENV))

    System.put_env(%{
      "SMTP_FROM" => "residual@test",
      "DOMAIN" => "www.example.com",
      "RAILS_ENV" => "staging"
    })

    on_exit(fn ->
      Enum.each(~w(SMTP_FROM DOMAIN RAILS_ENV), &System.delete_env/1)
      System.put_env(previous)
    end)

    row = @path |> File.read!() |> Jason.decode!() |> Map.fetch!("locations") |> hd()
    load(row)

    args = %{
      "request_id" => row["request_id"],
      "user_id" => row["target_id"],
      "event_id" => Ecto.UUID.generate()
    }

    assert LocationRequestWorker.perform(%Oban.Job{args: args}) == :ok

    receive do
      {:mail, _} -> flunk("foreign request reached SMTP")
    after
      0 -> :ok
    end

    assert rows("SELECT count(*) FROM phoenix.delivery_claims") == [[0]]
  end

  defp load(row) do
    for {id, email, locale} <- [
          {row["requester_id"], row["requester_email"], "en"},
          {row["target_id"], row["recipient"], "de"}
        ] do
      DigestFixtures.row!(ScratchRepo, "users", %{
        "id" => id,
        "email" => email,
        "settings" => %{"locale" => locale},
        "created_at" => @now,
        "updated_at" => @now
      })
    end

    rows(
      "INSERT INTO public.families(id,name,creator_id,created_at,updated_at) VALUES(460400,'Synthetic family',$1,$2,$2)",
      [row["requester_id"], @now]
    )

    status =
      case row["status"] do
        "accepted" -> 1
        "expired" -> 3
        _ -> 0
      end

    expires =
      if row["expired"], do: NaiveDateTime.add(@now, -3600), else: NaiveDateTime.add(@now, 86400)

    rows(
      "INSERT INTO public.family_location_requests(id,requester_id,target_user_id,family_id,status,suggested_duration,expires_at,created_at,updated_at) VALUES($1,$2,$3,460400,$4,'24h',$5,$6,$6)",
      [row["request_id"], row["requester_id"], row["target_id"], status, expires, @now]
    )
  end
end
