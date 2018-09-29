defmodule Persisted do
  use Ekv, path: "tmp/persisted", table_name: :persisted
end
