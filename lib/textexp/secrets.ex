defmodule Textexp.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Textexp.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:textexp, :token_signing_secret)
  end
end
