defmodule Dawarich.ApiProtocolClearFailure do
  defdelegate one(query, opts), to: Dawarich.Repo
  defdelegate query!(sql, params, opts), to: Dawarich.Repo

  def update!(changeset, opts) do
    if Map.has_key?(changeset.changes, :otp_secret) and is_nil(changeset.changes.otp_secret),
      do: raise("A4 OTP expected clear failure"),
      else: Dawarich.Repo.update!(changeset, opts)
  end
end

defmodule Dawarich.Auth.ApiProtocol do
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.TwoFactor.{Api, Totp}
  alias Dawarich.Repo

  def write(path, env) do
    ids = [954_801, 954_802, 954_803]
    emails = Enum.map(ids, &"a4otp-protocol-#{&1}@example.invalid")
    now = ~U[2026-10-04 12:00:00.000000Z]
    password = "safepassword12"
    hash = Bcrypt.hash_pwd_salt(password, log_rounds: 4)

    context = %{
      self_hosted: true,
      env: env,
      clock: fn -> now end,
      backup_options: [log_rounds: 4]
    }

    projection = fn id ->
      actor = Repo.get!(Account, id, log: false)

      %{
        "enabled" => actor.otp_required_for_login,
        "ciphertext" => actor.otp_secret,
        "backups" => actor.otp_backup_codes,
        "consumed_timestep" => actor.consumed_timestep
      }
    end

    [[count]] =
      Repo.query!(
        "SELECT count(*) FROM users WHERE id=ANY($1) OR email=ANY($2)",
        [ids, emails],
        log: false
      ).rows

    unless count == 0, do: raise("A4 OTP synthetic actor already exists")

    rows =
      Enum.zip_with(ids, emails, fn id, email ->
        %{
          id: id,
          email: email,
          encrypted_password: hash,
          status: 1,
          plan: 1,
          settings: %{},
          api_key: "A4OTP_PROTOCOL_#{id}",
          created_at: now,
          updated_at: now
        }
      end)

    {3, _} = Repo.insert_all("users", rows, log: false)

    try do
      actors =
        Enum.map(ids, fn id ->
          params = %{"password" => password}

          {secret, current, codes} =
            if id == 954_803 do
              {:ok, 200, {:object, [{"backup_codes", codes}]}} =
                Api.run(:backup_codes, id, params, context)

              {nil, nil, codes}
            else
              {:ok, 200, {:object, setup}} = Api.run(:setup, id, params, context)
              secret = setup |> Map.new() |> Map.fetch!("secret")
              current = Totp.at(secret, DateTime.to_unix(now))

              {:ok, 200, {:object, [{"backup_codes", _}]}} =
                Api.run(:confirm, id, Map.put(params, "otp_code", current), context)

              {:ok, 200, {:object, [{"backup_codes", codes}]}} =
                Api.run(:backup_codes, id, params, context)

              {secret, current, codes}
            end

          confirmed = projection.(id)

          consumed =
            if id == 954_802 do
              try do
                Api.run(
                  :destroy,
                  id,
                  Map.put(params, "otp_code", current),
                  Map.put(context, :repo, Dawarich.ApiProtocolClearFailure)
                )

                raise "A4 OTP clear failure did not occur"
              rescue
                error in RuntimeError ->
                  unless error.message == "A4 OTP expected clear failure",
                    do: reraise(error, __STACKTRACE__)
              end

              projection.(id)
            else
              nil
            end

          {:ok, 200, _} = Api.run(:destroy, id, Map.put(params, "otp_code", hd(codes)), context)

          %{
            "id" => id,
            "email" => "a4otp-protocol-#{id}@example.invalid",
            "hash" => hash,
            "secret" => secret,
            "current_code" => current,
            "later_code" => if(secret, do: Totp.at(secret, DateTime.to_unix(now) + 30)),
            "unused_backup" => Enum.at(codes, 1),
            "confirmed" => confirmed,
            "consumed" => consumed,
            "disabled" => projection.(id)
          }
        end)

      result = %{
        "mode" => "api_two_factor_management",
        "schema" => 1,
        "summary" => "API storage only; no session issued",
        "password" => password,
        "at" => DateTime.to_unix(now),
        "actors" => actors
      }

      File.write!(path, Jason.encode!(result))
      File.chmod!(path, 0o600)
    after
      Repo.query!("DELETE FROM users WHERE id=ANY($1) AND email=ANY($2)", [ids, emails],
        log: false
      )
    end
  end
end
