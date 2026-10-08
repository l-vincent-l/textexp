[
  import_deps: [
    :ash_authentication,
    :ash_authentication_phoenix,
    :ash_admin,
    :ash_phoenix,
    :ash,
    :reactor,
    :ecto,
    :ecto_sql,
    :phoenix,
    :ash_sqlite
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
