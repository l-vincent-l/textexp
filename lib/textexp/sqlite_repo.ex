defmodule Textexp.SqliteRepo do
  use AshSqlite.Repo,
    otp_app: :textexp,
    adapter: Ecto.Adapters.LibSql
end
