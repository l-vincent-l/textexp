defmodule Textexp.Accounts do
  use Ash.Domain,
    otp_app: :textexp

  resources do
    resource Textexp.Accounts.Token
    resource Textexp.Accounts.User
  end
end
