defmodule Textexp.Document do
  use Ash.Domain,
    otp_app: :textexp,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Textexp.Document.Document do
      define :create_document, action: :create
      define :get_document, action: :read, get_by: [:id]
      define :list_documents, action: :read
      define :rename_document, action: :rename, args: [:title]
      define :save_snapshot, action: :save_snapshot, args: [:snapshot]
    end
  end
end
