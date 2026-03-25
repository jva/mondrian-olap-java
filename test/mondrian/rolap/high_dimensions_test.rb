# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/HighDimensionsTest.java
describe "HighDimensions" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Java: HighDimensionsTest#testBug1971406
  it "bug 1971406 NonEmptyCrossJoin performance" do
    skip unless mondrian_property(:EnableNativeCrossJoin).get

    mdx = <<~MDX
      WITH SET necj AS
        NonEmptyCrossJoin(
          NonEmptyCrossJoin(
            [Customers].[Name].Members,
            [Store].[Store Name].Members),
          [Product].[Product Name].Members)
      SELECT {[Measures].[Unit Sales]} ON COLUMNS,
        Tail(Intersect(necj, necj, ALL), 5) ON ROWS
      FROM [Sales]
    MDX

    t0 = java.lang.System.currentTimeMillis
    result = @olap.execute(mdx)
    cell_set = result.raw_cell_set
    axis = cell_set.getAxes.get(0)
    axis.getPositions.each do |position|
      refute_nil position.getMembers.get(0)
    end
    elapsed = java.lang.System.currentTimeMillis - t0

    # ~3.8s on Apple M2 MacBook. Adjust if your hardware is slower.
    target = 4_500
    assert elapsed <= target,
      "Query execution took #{elapsed}ms, which is outside target of #{target}ms"
  end

  # Java: HighDimensionsTest#testPromotionsTwoDimensions
  it "promotions two dimensions" do
    skip "Bug MONDRIAN-486 not fixed"
  end

  # Java: HighDimensionsTest#testHead
  it "Head function on high cardinality dimension" do
    skip "Bug MONDRIAN-486 not fixed"
  end

  # Java: HighDimensionsTest#testNonEmpty
  it "NON EMPTY on high cardinality dimension" do
    skip "Bug MONDRIAN-486 not fixed"
  end

  # Java: HighDimensionsTest#testFilter
  it "FILTER on high cardinality dimension" do
    skip "Bug MONDRIAN-486 not fixed"
  end

  # Java: HighDimensionsTest#testMondrian1488
  it "MONDRIAN-1488 null values in high cardinality dimension" do
    # MONDRIAN-1501 / MONDRIAN-1488
    # Both involve an attempt to modify the list backing
    # HighCardSqlTupleReader when handling null values.
    # Requires use of a dim flagged as high card which has null members.
    cube_xml = <<~XML
      <Cube name="highCard">
        <Table name="sales_fact_1997"/>
        <Dimension name="StoreSize" foreignKey="customer_id" highCardinality="true">
          <Hierarchy hasAll="true" primaryKey="store_id">
            <Table name="store"/>
            <Level name="Sqft" column="store_sqft" type="Numeric" uniqueMembers="true"/>
          </Hierarchy>
        </Dimension>
        <Measure name="Unit Sales" column="unit_sales" aggregator="sum"/>
      </Cube>
    XML
    schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    olap = Mondrian::OLAP::Connection.create(params)
    begin
      # This will throw an exception if .remove is called on the HCSTR list
      result = olap.execute(
        "SELECT NON EMPTY Filter([StoreSize].[Sqft].Members, 1=1) ON 0 FROM [highCard]"
      )
      refute_nil result
    ensure
      olap.close
    end
  end
end
