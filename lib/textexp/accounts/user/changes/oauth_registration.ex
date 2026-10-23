defmodule Textexp.Accounts.User.Changes.OAuthRegistration do
  @moduledoc """
  Registers, or signs in, a user with the email address their GitHub or
  GitLab account gives, which the provider must have verified: otherwise
  anyone could declare someone else's address there, and get here a confirmed
  account in their name, that the owner of the address would later sign in to
  (by magic link or password reset) while the provider account keeps access.

  An existing account with that address is signed in only if its owner
  confirmed it: otherwise, whoever controls the address at the provider would
  take over an account its owner never validated. AshAuthentication already
  ensures it (`prevent_hijacking?`: the upsert only matches a confirmed
  account); this is checked again after the upsert, as its guide advises.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info)

    if user_info["email_verified"] == true do
      register(changeset, user_info)
    else
      Ash.Changeset.add_error(changeset,
        field: :email,
        message: "the provider has not verified this email address"
      )
    end
  end

  defp register(changeset, user_info) do
    changeset
    |> Ash.Changeset.change_attribute(:email, user_info["email"])
    |> Ash.Changeset.after_action(fn _changeset, user ->
      case user.confirmed_at do
        nil -> {:error, "An unconfirmed account already exists with this email address"}
        _ -> {:ok, user}
      end
    end)
  end
end
