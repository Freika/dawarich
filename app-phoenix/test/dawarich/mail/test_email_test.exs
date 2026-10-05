defmodule Dawarich.Mail.TestEmailTest do
  use Dawarich.JobsCase

  import ExUnit.CaptureLog
  alias Dawarich.DigestFixtures
  alias Dawarich.Mail.{DeviseResidual, Residual, ResidualCommands, TestEmail}
  alias Dawarich.Mail.Digests.{DeliveryWorker, Enqueue, Render}

  @http Path.expand("../../fixtures/mail/residual/http.json", __DIR__)
  @content Path.expand("../../fixtures/mail/residual/content.json", __DIR__)
  @digests Path.expand("../../fixtures/mail/residual/digest_content.json", __DIR__)
  @clock %{local: ~N[2026-10-04 12:00:00], offset: 0, zone: "UTC", valid: true}
  @env %{
    "SMTP_SERVER" => "synthetic.test",
    "SMTP_AUTHENTICATION" => "none",
    "SMTP_STARTTLS" => "false",
    "SMTP_FROM" => "Dawarich <residual@dawarich.test>",
    "TIME_ZONE" => "UTC"
  }
  @markers ["a12c-body-marker", "a12c-raw-token", "https://synthetic.test/?token=a12c-raw-token"]

  test "test email attempts one immediate send and matches configured and safe failure outcomes" do
    start_oban(:residual_test_email)
    cases = @http |> File.read!() |> Jason.decode!() |> Map.fetch!("cases")

    names =
      ~w(html_success not_configured preferred_de socket_error timeout_error ssl_error system_error argument_error smtp_error unsafe_error smtp_fatal smtp_busy smtp_syntax smtp_auth_reply smtp_unknown smtp_multiline)

    cases = Enum.filter(cases, &(&1["id"] in names))
    assert length(cases) == length(names)
    before = counts()

    for row <- cases do
      recipient = %{email: row["recipient"], settings: %{"locale" => row["preference"]}}
      env = if row["configured"], do: @env, else: Map.delete(@env, "SMTP_SERVER")

      Process.put(:transport_result, Dawarich.Mail.TestTransport.result(row))
      expected = row["response"]["flash"]
      [{kind, description}] = Map.to_list(expected)

      for _ <- 1..2 do
        assert TestEmail.run(recipient, "en", env, clock: @clock) ==
                 {String.to_existing_atom(kind), description}

        if row["configured"] do
          assert_received {:mail, message}
          assert message.to == recipient.email
          assert message.format == :html_only

          expected_content =
            @content
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("cases")
            |> Enum.find(
              &(&1["id"] ==
                  if(row["id"] == "preferred_de", do: "test_email_de", else: "test_email_en"))
            )

          assert message.subject == expected_content["subject"]
        else
          refute_received {:mail, _}
        end

        refute_received {:mail, _}
        assert counts() == before
      end

      Process.delete(:transport_result)
    end

    assert TestEmail.supported?(Map.put(@env, "SMTP_AUTHENTICATION", "unsupported")) == false
    assert TestEmail.supported?(Map.put(@env, "SMTP_AUTHENTICATION", "plain")) == false
    assert TestEmail.supported?(Map.put(@env, "SMTP_STARTTLS", "true")) == false
    assert TestEmail.supported?(Map.put(@env, "SMTP_SSL", "true")) == false
    assert TestEmail.supported?(@env) == true
    assert TestEmail.supported?(Map.delete(@env, "SMTP_SERVER")) == true
  end

  test "mail success and render enqueue transport failures never log body or token markers" do
    start_oban(:residual_log)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    for spec <- Dawarich.Redis.child_specs() ++ Dawarich.Redis.cache_child_specs(),
        do: start_supervised!(spec)

    Dawarich.Test.RailsUser.insert!(%{
      id: 460_006,
      email: "a12c-body-marker@test",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    names =
      ~w(SMTP_FROM SMTP_SERVER SMTP_AUTHENTICATION SMTP_STARTTLS SELF_HOSTED TIME_ZONE DOMAIN RAILS_ENV)

    previous = Map.take(System.get_env(), names)
    routes = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, [])

    System.put_env(%{
      "SMTP_FROM" => @env["SMTP_FROM"],
      "SMTP_SERVER" => "synthetic.test",
      "SMTP_AUTHENTICATION" => "none",
      "SMTP_STARTTLS" => "false",
      "SELF_HOSTED" => "true",
      "TIME_ZONE" => "UTC",
      "DOMAIN" => "synthetic.test",
      "RAILS_ENV" => "staging"
    })

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_routes, routes)
      Enum.each(names, &System.delete_env/1)
      System.put_env(previous)
    end)

    user = %{id: 460_001, email: "a12c-body-marker@test", settings: %{"locale" => "en"}}

    DigestFixtures.row!(ScratchRepo, "users", %{
      "id" => user.id,
      "email" => user.email,
      "settings" => user.settings,
      "created_at" => @clock.local,
      "updated_at" => @clock.local
    })

    template =
      @digests
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Enum.find(&(&1["id"] == "monthly_km"))

    digest =
      Map.merge(template["digest"], %{
        "user_id" => user.id,
        "id" => 460_002,
        "period_type" => 0,
        "created_at" => @clock.local,
        "updated_at" => @clock.local
      })

    DigestFixtures.row!(ScratchRepo, "digests", digest)
    digest = Map.put(digest, "period_type", "monthly")

    log =
      capture_log(fn ->
        for kind <- [:otp_account_locked, :location_request] do
          message =
            Residual.message(kind, user, "en", @env,
              base_url: List.last(@markers),
              requester: Enum.join(@markers),
              request_id: 460_003
            )

          assert is_map(message)
        end

        for kind <- [:email_changed, :password_change] do
          assert is_map(
                   DeviseResidual.message(
                     kind,
                     Enum.join(@markers),
                     Enum.join(@markers),
                     "en",
                     @env
                   )
                 )

          assert_raise Protocol.UndefinedError, fn ->
            DeviseResidual.message(
              kind,
              Enum.join(@markers),
              {"invalid", Enum.join(@markers)},
              "en",
              @env
            )
          end
        end

        assert is_map(Render.message(ScratchRepo, user, digest, "en", @env, List.last(@markers)))

        assert_raise ArgumentError, fn ->
          Render.message(
            ScratchRepo,
            user,
            Map.put(digest, "monthly_distances", Enum.join(@markers)),
            "en",
            @env,
            List.last(@markers)
          )
        end

        payload = %{
          "user_id" => user.id,
          "year" => 2024,
          "month" => 2,
          "time_zone" => "UTC",
          "locale" => "fr",
          "event_id" => Ecto.UUID.generate()
        }

        Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:mail.digest.monthly", :oban)
        Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:mail.family_location_request", :oban)
        assert ResidualCommands.digest(ScratchRepo, "monthly", payload) == :ok

        assert ResidualCommands.location(ScratchRepo, %{
                 "user_id" => user.id,
                 "request_id" => 460_003
               }) == :ok

        rows(
          "ALTER TABLE oban.oban_jobs ADD CONSTRAINT a12c_log_enqueue CHECK (worker <> 'Dawarich.Mail.Digests.DeliveryWorker')"
        )

        assert match?(
                 {:error, _},
                 Enqueue.run(ScratchRepo, "monthly", payload, oban: :residual_log)
               )

        rows("ALTER TABLE oban.oban_jobs DROP CONSTRAINT a12c_log_enqueue")
        assert Enqueue.run(ScratchRepo, "monthly", payload, oban: :residual_log) == :ok
        [[args]] = rows("SELECT args FROM oban.oban_jobs")
        Process.put(:transport_result, {:error, Enum.join(@markers)})
        assert match?({:error, _}, DeliveryWorker.perform(%Oban.Job{args: args}))

        receive do
          {:mail, _} -> :ok
        after
          0 -> flunk("transport was not called")
        end

        Process.delete(:transport_result)
        assert DeliveryWorker.perform(%Oban.Job{args: args}) == :ok

        receive do
          {:mail, _} -> :ok
        after
          0 -> flunk("transport was not called")
        end

        assert elem(TestEmail.run(user, "en", @env, clock: @clock), 0) == :notice

        receive do
          {:mail, _} -> :ok
        after
          0 -> flunk("transport was not called")
        end

        Process.put(:transport_result, {:error, {"IOError", Enum.join(@markers)}})
        assert elem(TestEmail.run(user, "en", @env, clock: @clock), 0) == :alert

        receive do
          {:mail, _} -> :ok
        after
          0 -> flunk("transport was not called")
        end

        Process.delete(:transport_result)
        assert elem(TestEmail.run(user, "en", @env, clock: %{}), 0) == :alert
        refute_received {:mail, _}

        DigestFixtures.row!(ScratchRepo, "users", %{
          "id" => 460_004,
          "email" => Enum.join(@markers),
          "settings" => %{"locale" => "en"},
          "created_at" => @clock.local,
          "updated_at" => @clock.local
        })

        rows(
          "INSERT INTO public.families(id,name,creator_id,created_at,updated_at) VALUES(460005,'Synthetic family',460004,$1,$1)",
          [@clock.local]
        )

        rows(
          "INSERT INTO public.family_location_requests(id,requester_id,target_user_id,family_id,status,suggested_duration,expires_at,created_at,updated_at) VALUES(460003,460004,$1,460005,0,'24h',$2,$3,$3)",
          [user.id, NaiveDateTime.add(@clock.local, 86400), @clock.local]
        )

        location = %{
          "user_id" => 460_004,
          "request_id" => 460_003,
          "event_id" => Ecto.UUID.generate()
        }

        for failure <- [true, false] do
          if failure,
            do: Process.put(:transport_result, {:error, Enum.join(@markers)}),
            else: Process.delete(:transport_result)

          result = Dawarich.Mail.LocationRequestWorker.perform(%Oban.Job{args: location})
          assert match?({:error, _}, result) == failure

          receive do
            {:mail, _} -> :ok
          after
            0 -> flunk("location transport was not called")
          end
        end

        raw = Enum.at(@markers, 1)
        secret = Dawarich.RailsSecret.fetch()
        token_digest = Dawarich.Auth.Recovery.Token.digest(:reset_password_token, raw, secret)

        rows("UPDATE public.users SET reset_password_token=$2 WHERE id=$1", [
          user.id,
          token_digest
        ])

        notification = %Dawarich.Auth.Recovery.Notification{
          kind: :reset_password_instructions,
          user_id: user.id,
          raw: raw,
          digest: token_digest,
          locale: "en"
        }

        assert Dawarich.Auth.Recovery.MailWorker.enqueue(notification, :residual_log) == :ok
        [[recovery]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id DESC LIMIT 1")

        for failure <- [true, false] do
          if failure,
            do: Process.put(:transport_result, {:error, Enum.join(@markers)}),
            else: Process.delete(:transport_result)

          result = Dawarich.Auth.Recovery.MailWorker.perform(%Oban.Job{args: recovery})
          assert match?({:error, _}, result) == failure

          receive do
            {:mail, _} -> :ok
          after
            0 -> flunk("recovery transport was not called")
          end
        end

        path = "/settings/general/test_email"
        session = Dawarich.Test.RailsUser.session(460_006)

        for accept <- ["text/html", "text/vnd.turbo-stream.html"], failure <- [false, true] do
          if failure,
            do: Process.put(:transport_result, {:error, {"IOError", Enum.join(@markers)}}),
            else: Process.delete(:transport_result)

          conn =
            Phoenix.ConnTest.build_conn()
            |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
            |> Plug.Conn.put_req_header("content-length", "0")
            |> Plug.Conn.put_req_header("accept", accept)
            |> Plug.Conn.put_req_header(
              "x-csrf-token",
              DawarichWeb.RailsCsrf.masked_form_token(session, path, "POST")
            )
            |> Plug.Test.put_req_cookie(
              "_dawarich_session",
              Dawarich.Test.RailsUser.cookie(session)
            )

          response = Phoenix.ConnTest.dispatch(conn, DawarichWeb.Endpoint, "POST", path, "")
          assert response.status == if(accept == "text/html", do: 302, else: 200)

          assert Plug.Conn.get_resp_header(response, "x-dawarich-mail-owner") == [
                   "native-test-email"
                 ]

          receive do
            {:mail, _} -> :ok
          after
            0 -> flunk("HTTP transport was not called")
          end

          refute_received {:mail, _}
          Process.delete(:transport_result)

          fault = %{
            conn
            | method: "POST",
              request_path: path,
              query_string: "",
              path_info: String.split(path, "/", trim: true)
          }

          response = DawarichWeb.TestEmail.call(fault, clock: %{})
          assert response.status == if(accept == "text/html", do: 302, else: 200)

          assert Plug.Conn.get_resp_header(response, "x-dawarich-mail-owner") == [
                   "native-test-email"
                 ]

          refute_received {:mail, _}
        end
      end)

    for marker <- @markers,
        do: refute(String.contains?(log, marker), "sensitive mail marker logged")
  end

  defp counts do
    for table <-
          ~w(public.users public.digests public.job_outbox oban.oban_jobs phoenix.delivery_claims),
        into: %{} do
      [[count]] = rows("SELECT count(*) FROM #{table}")
      {table, count}
    end
  end
end
