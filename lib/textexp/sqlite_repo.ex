defmodule Textexp.SqliteRepo do
  # A local SQLite file, or a libSQL server: see :repo_adapter in
  # config/config.exs.
  use AshSqlite.Repo,
    otp_app: :textexp,
    adapter: Application.compile_env(:textexp, :repo_adapter, Ecto.Adapters.SQLite3)
end
