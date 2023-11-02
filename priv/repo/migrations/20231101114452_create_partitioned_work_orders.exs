defmodule Lightning.Repo.Migrations.CreatePartitionedWorkOrders do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE work_orders
    RENAME TO work_orders_monolith
    """)

    execute("""
    ALTER TABLE work_orders
    RENAME CONSTRAINT work_orders_pkey TO work_orders_monolith_pkey
    """)

    execute("""
    CREATE TABLE public.work_orders (
    id uuid NOT NULL,
    workflow_id uuid NOT NULL,
    reason_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    trigger_id uuid,
    dataclip_id uuid,
    state character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    last_activity timestamp without time zone
    CONSTRAINT work_orders_pkey PRIMARY_KEY(id, inserted_at)
    ) PARTITION BY RANGE (inserted_at);
    """)

    execute("""
    """)
  end

  def down do
    execute("""
      DROP TABLE IF EXISTS public.work_orders
    """)

    execute("""
    ALTER TABLE work_orders_monolith
    RENAME TO work_orders
    """)

    execute("""
    ALTER TABLE work_orders
    RENAME CONSTRAINT work_orders_monolith_pkey TO work_orders_pkey
    """)
  end
end
