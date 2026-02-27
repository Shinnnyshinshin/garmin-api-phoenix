defmodule GarminPlanner.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: GarminPlanner.Vault
end
