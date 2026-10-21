defmodule Dawarich.Auth.AccountValidationTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.AccountValidation

  test "matches every source credential validation row" do
    rows = "test/fixtures/auth/account/validation.json" |> File.read!() |> Jason.decode!()
    requests = "test/fixtures/auth/account/requests.json" |> File.read!() |> Jason.decode!()

    indices =
      requests |> Enum.with_index() |> Map.new(fn {row, index} -> {row["name"], index} end)

    for row <- rows do
      id = 73_400 + indices[row["name"]]
      current_email = "a11rest-#{id}@dawarich.test"
      input = Map.merge(%{"email" => "changed", "current_password" => "valid"}, row["input"])
      params = params(input, current_email, id)

      result =
        AccountValidation.validate(params, current_email,
          current_password_valid: input["current_password"] == "valid",
          email_taken: input["email"] in ["taken", "deleted"],
          locale: row["locale"]
        )

      assert result.render.messages == row["errors"], row["name"]
      assert Enum.empty?(result.errors) == (row["status"] == 303), row["name"]

      if row["status"] == 422 do
        assert result.render.email == row["submitted_email"], row["name"]
      end

      assert Map.keys(result.render) |> Enum.sort() == [:email, :errors, :messages]
      refute Map.has_key?(result.changes, :password_confirmation)
      refute Map.has_key?(result.changes, :current_password)
    end

    for blank <- ["", " \t\n", " ", "　"] do
      result =
        AccountValidation.validate(
          %{"password" => blank, "password_confirmation" => blank, "current_password" => "valid"},
          "a11rest@test",
          current_password_valid: true
        )

      assert result.changes == %{}
      assert result.errors == []
    end

    combining = String.duplicate("e" <> <<0xCC, 0x81>>, 6)

    result =
      AccountValidation.validate(
        %{"password" => combining, "current_password" => "valid"},
        "a11rest@test",
        current_password_valid: true
      )

    assert result.errors == []
    assert result.changes.password == combining
  end

  defp params(input, email, id) do
    input
    |> Map.take(~w(email password password_confirmation current_password))
    |> Enum.reject(fn {_field, marker} -> marker == "omitted" end)
    |> Map.new(fn {field, marker} ->
      value =
        cond do
          field == "email" ->
            %{
              "same" => email,
              "changed" => "a11rest-changed-#{id}@dawarich.test",
              "normalized" => " A11REST-NORMALIZED-#{id}@dawarich.test ",
              "taken" => "A11REST-TAKEN@dawarich.test",
              "deleted" => "a11rest-deleted@dawarich.test",
              "invalid" => "<bad>",
              "empty" => ""
            }[marker]

          String.starts_with?(marker, "repeat_") ->
            [_, character, count] = String.split(marker, "_")
            String.duplicate(character, String.to_integer(count))

          true ->
            %{
              "valid" => "a11rest-password-42",
              "new" => "a11rest-new-password",
              "empty" => "",
              "wrong" => "wrong-password",
              "short" => "short"
            }[marker]
        end

      {field, value}
    end)
  end
end
