defmodule Textexp.Accounts.OAuthTest do
  use TextexpWeb.ConnCase

  alias AshAuthentication.{Info, Strategy}
  alias Textexp.Accounts.{User, UserIdentity}

  # What GitHub (through Assent) gives about the account.
  defp github_user_info(email) do
    %{
      "sub" => "#{System.unique_integer([:positive])}",
      "email" => email,
      "email_verified" => true
    }
  end

  defp register(user_info, provider \\ :github) do
    User
    |> Info.strategy!(provider)
    |> Strategy.action(:register, %{
      "user_info" => user_info,
      "oauth_tokens" => %{"access_token" => "token", "token_type" => "bearer"}
    })
  end

  defp register_with_password(email) do
    User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: email,
      password: "a-long-password",
      password_confirmation: "a-long-password"
    })
    |> Ash.create!(authorize?: false)
  end

  test "the sign-in page offers GitHub and GitLab", %{conn: conn} do
    html = conn |> get(~p"/sign-in") |> html_response(200)

    assert html =~ ~s(href="/auth/user/github")
    assert html =~ ~s(href="/auth/user/gitlab")
    assert html =~ "/images/gitlab.svg"
  end

  test "registers a new user, and recognises them when they come back" do
    user_info = github_user_info("octo-#{System.unique_integer([:positive])}@example.com")

    assert {:ok, user} = register(user_info)
    assert to_string(user.email) == user_info["email"]
    assert user.confirmed_at

    identities =
      UserIdentity |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.user_id == user.id))

    assert [%{strategy: "github", uid: uid}] = identities
    assert uid == user_info["sub"]

    assert {:ok, again} = register(user_info)
    assert again.id == user.id
  end

  test "signs in the confirmed account with the same email" do
    email = "confirmed-#{System.unique_integer([:positive])}@example.com"

    existing = Ash.Seed.seed!(User, %{email: email, confirmed_at: DateTime.utc_now()})

    assert {:ok, user} = register(github_user_info(email))
    assert user.id == existing.id
  end

  test "refuses an unconfirmed account with the same email" do
    email = "unconfirmed-#{System.unique_integer([:positive])}@example.com"
    register_with_password(email)

    assert {:error, error} = register(github_user_info(email))
    # AshAuthentication's own guard (prevent_hijacking?): the upsert only
    # matches a confirmed account. The reason is not shown to the user.
    assert inspect(error) =~ "not is_nil(confirmed_at)"
  end

  test "registers a new user with GitLab" do
    user_info = github_user_info("tanuki-#{System.unique_integer([:positive])}@example.com")

    assert {:ok, user} = register(user_info, :gitlab)
    assert to_string(user.email) == user_info["email"]

    assert [%{strategy: "gitlab"}] =
             UserIdentity |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.user_id == user.id))
  end

  # Otherwise anyone could declare someone else's address at the provider and
  # get a confirmed account in their name here.
  test "refuses an email address the provider has not verified" do
    email = "unverified-#{System.unique_integer([:positive])}@example.com"
    user_info = %{github_user_info(email) | "email_verified" => false}

    assert {:error, error} = register(user_info)
    assert inspect(error) =~ "the provider has not verified this email address"
    assert {:error, _} = Ash.get(User, %{email: email}, authorize?: false)
  end

  test "a failed sign-in with GitHub says so", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])
      |> TextexpWeb.AuthController.failure({:github, :callback}, :any_reason)

    assert redirected_to(conn) == ~p"/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Signing in with GitHub failed"
  end
end
