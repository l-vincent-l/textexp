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

  # The OAuth applications of GitHub and GitLab, configured in
  # config/runtime.exs. An unset value fails the sign-in with that provider.
  def secret_for(
        [:authentication, :strategies, provider, key],
        Textexp.Accounts.User,
        _opts,
        _context
      )
      when provider in [:github, :gitlab] do
    case :textexp |> Application.get_env(provider, []) |> Keyword.get(key) do
      nil -> :error
      value -> {:ok, value}
    end
  end
end
