defmodule Textexp.Document do
  use Ash.Domain,
    otp_app: :textexp,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Textexp.Document.Writing
  end
end
