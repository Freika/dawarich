defmodule Dawarich.Admin.UserValidationTest do
  use ExUnit.Case, async: true
  alias Dawarich.Admin.UserValidation

  test "matches admin strong params normalization and validation messages" do
    assert Code.ensure_loaded?(UserValidation), "admin user validation must exist"

    for {name, params, context} <- [
          {"duplicate_en", %{"email" => "taken@example.invalid", "password" => password()},
           %{email_taken: true}},
          {"duplicate_de", %{"email" => "taken@example.invalid", "password" => password()},
           %{email_taken: true, locale: "de"}},
          {"invalid_email", %{"email" => "invalid", "password" => password()}, %{}},
          {"blank_email", %{"email" => "", "password" => password()}, %{}},
          {"short_password", %{"email" => "new@example.invalid", "password" => "short"}, %{}},
          {"blank_password", %{"email" => "new@example.invalid", "password" => ""}, %{}},
          {"long_password",
           %{"email" => "new@example.invalid", "password" => String.duplicate("x", 129)}, %{}}
        ] do
      assert {:invalid, message} = UserValidation.create(params, context)
      assert message == fixture(name)["flash"]["alert"], name
    end

    for value <- [
          String.duplicate("x", 12),
          String.duplicate("x", 128),
          String.duplicate("é", 12),
          String.duplicate("e" <> <<0xCC, 0x81>>, 6)
        ] do
      assert {:ok, changes} =
               UserValidation.create(
                 %{
                   "email" => " NEW@example.invalid ",
                   "password" => value,
                   "admin" => "1",
                   "status" => "inactive"
                 },
                 %{}
               )

      assert changes == %{email: "new@example.invalid", password: value}
    end

    target = %{id: 1, email: "target@example.invalid", admin: false, status: 1}

    for value <- [nil, "", " \t\n", " ", "　"] do
      assert {:ok, changes} = UserValidation.update(target, %{"password" => value}, %{})
      refute Map.has_key?(changes, :password)
    end

    assert {:ok, %{email: "changed@example.invalid", password: "new-synthetic-password"}} =
             UserValidation.update(
               target,
               %{
                 "email" => " CHANGED@example.invalid ",
                 "password" => "new-synthetic-password",
                 "current_password" => "wrong",
                 "password_confirmation" => "wrong"
               },
               %{}
             )

    assert {:invalid, message} = UserValidation.update(target, %{"email" => ""}, %{})
    assert message == fixture("update_invalid")["flash"]["alert"]

    for locale <- ["en", "de"] do
      assert {:invalid, message} =
               UserValidation.create(%{"email" => "invalid", "password" => "short"}, %{
                 locale: locale
               })

      expected =
        if locale == "en",
          do:
            "User could not be created: Email is invalid and Password is too short (minimum is 12 characters)",
          else:
            "Benutzer konnte nicht erstellt werden: Email ist nicht gültig und Password ist zu kurz (weniger als 12 Zeichen)"

      assert message == expected
    end
  end

  test "matches status role casts and invalid values" do
    assert Code.ensure_loaded?(UserValidation), "admin user validation must exist"
    target = %{id: 1, email: "target@example.invalid", admin: false, status: 1}

    for {value, expected} <- [
          {"inactive", 0},
          {"active", 1},
          {"trial", 2},
          {"pending_payment", 3},
          {0, 0},
          {1, 1},
          {2, 2},
          {3, 3},
          {"", nil},
          {nil, nil}
        ] do
      assert {:ok, changes} = UserValidation.update(target, %{"status" => value}, %{})
      assert changes == if(expected == target.status, do: %{}, else: %{status: expected})
    end

    for value <- ["unknown", "1", 4] do
      assert {:handoff, :invalid_status} =
               UserValidation.update(target, %{"status" => value}, %{})
    end

    for {value, expected} <- [
          {"0", false},
          {"false", false},
          {"FALSE", false},
          {"f", false},
          {"F", false},
          {"off", false},
          {"OFF", false},
          {false, false},
          {0, false},
          {"", nil},
          {nil, nil},
          {"1", true},
          {"true", true},
          {"False", true},
          {"yes", true}
        ] do
      assert {:ok, changes} = UserValidation.update(target, %{"admin" => value}, %{})
      assert changes == if(expected == target.admin, do: %{}, else: %{admin: expected})
    end

    assert {:ok, %{}} = UserValidation.update(target, %{"ignored" => "value"}, %{})
    raw = %{"admin" => "false", "status" => 1}
    assert {:ok, changes} = UserValidation.update(target, raw, %{})
    assert changes == %{}
    assert raw == %{"admin" => "false", "status" => 1}
  end

  defp password, do: "a10b-synthetic-password"

  defp fixture(name),
    do: File.read!("test/fixtures/admin_mutations/#{name}.json") |> Jason.decode!()
end
