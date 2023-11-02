defmodule Lightning.PartitionTableServiceTest do
  use Lightning.DataCase

  alias Lightning.PartitionTableService, as: Service

  test "gets a list of partitions for a given parent" do
    assert length(Service.get_partitions("work_orders")) > 10
  end

  test "tables_to_add" do
    # Very vague test, given that this number change over time and at the end
    # of the year new partitions will need to be created as the test db is
    # started - this casts a wide net to consider that there _should_ be some
    # existing partitions.

    tables_proposed = Service.tables_to_add("work_orders", 35)
    assert length(tables_proposed) > 5 and length(tables_proposed) < 35
  end

  test "add_headroom" do
    before_count = length(Service.get_partitions("work_orders"))

    Service.add_headroom(:work_orders, 35)

    after_count = length(Service.get_partitions("work_orders"))

    assert before_count < after_count
  end

  test "remove_empty" do
    partitions = Service.get_partitions("work_orders")

    weeks_ago = Timex.shift(DateTime.utc_now(), weeks: -6)

    Service.remove_empty("work_orders", weeks_ago)

    assert length(Service.get_partitions("work_orders")) < length(partitions)
  end
end
