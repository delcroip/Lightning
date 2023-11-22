defmodule Lightning.Repo.Migrations.RemoveFksBetweenLogLinesMonolithAndAttempts do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE log_lines_monolith
    DROP CONSTRAINT log_lines_monolith_attempt_id_fkey
    """)
  end

  def down do
    execute("""
    ALTER TABLE log_lines_monolith
    ADD CONSTRAINT log_lines_monolith_attempt_id_fkey
    FOREIGN KEY (attempt_id)
    REFERENCES attempts(id)
    ON DELETE CASCADE
    """)
  end
end
