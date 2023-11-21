defmodule Lightning.Repo.Migrations.RemoveLogLinesMonolith do
  use Ecto.Migration

  def up do
    execute("""
    DROP TABLE IF EXISTS log_lines_monolith;
    """)
  end

  def down do
  end
end
