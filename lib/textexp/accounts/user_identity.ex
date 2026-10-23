defmodule Textexp.Accounts.UserIdentity do
  @moduledoc """
  A GitHub or GitLab account linked to a user: the provider's stable
  identifier of the account (`uid`, for the `strategy`) and its OAuth tokens.
  A returning user is recognised by it, not by their email address.
  """
  use Ash.Resource,
    otp_app: :textexp,
    domain: Textexp.Accounts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAuthentication.UserIdentity]

  sqlite do
    table "user_identities"
    repo Textexp.SqliteRepo

    references do
      reference :user, on_delete: :delete
    end
  end

  user_identity do
    user_resource Textexp.Accounts.User
  end
end
