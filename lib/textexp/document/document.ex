defmodule Textexp.Document.Document do
  @moduledoc """
  Un document collaboratif.

  Son contenu Yjs est stocké dans `snapshot` : l'état complet, réécrit au plus
  toutes les 10 s pendant l'édition (voir `Textexp.Document.YPersistence`).
  """
  use Ash.Resource, otp_app: :textexp, domain: Textexp.Document, data_layer: AshSqlite.DataLayer

  sqlite do
    table "documents"
    repo Textexp.SqliteRepo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title]
      change relate_actor(:owner)
    end

    update :rename do
      accept [:title]
    end

    update :save_snapshot do
      description "Remplace le snapshot par l'état Yjs complet du document."
      require_atomic? false
      accept [:snapshot]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :snapshot, Textexp.Types.Blob
    timestamps()
  end

  relationships do
    belongs_to :owner, Textexp.Accounts.User do
      public? true
    end
  end

  calculations do
    # Le snapshot étant réécrit à chaque sauvegarde, c'est `updated_at` (qui
    # change aussi au renommage).
    calculate :last_update, :utc_datetime_usec, expr(updated_at)
  end
end
