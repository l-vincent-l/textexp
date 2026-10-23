defmodule Textexp.Accounts do
  use Ash.Domain,
    otp_app: :textexp

  resources do
    resource Textexp.Accounts.Token
    resource Textexp.Accounts.UserIdentity

    resource Textexp.Accounts.User do
      define :list_users_by_ids, action: :by_ids, args: [:ids]
    end
  end
end
