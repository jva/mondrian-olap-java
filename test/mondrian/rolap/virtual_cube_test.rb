# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2003-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/VirtualCubeTest.java
describe "VirtualCube" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  private

  # Create a connection with additional cubes and/or virtual cubes added to the FoodMart schema.
  # Java's TestContext.create(null, cubeXml, virtualCubeXml, ...) pattern.
  def connection_with_custom_schema(cube_xml: nil, virtual_cube_xml: nil)
    schema = SchemaHelper::FOODMART_SCHEMA.dup

    if cube_xml
      schema = schema.sub("<VirtualCube", "#{cube_xml}\n<VirtualCube")
    end

    if virtual_cube_xml
      schema = schema.sub("<Role", "#{virtual_cube_xml}\n<Role")
    end

    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  # Compare two queries: execute both and assert that the measure values
  # (everything after the first '}') are identical.
  # Mirrors Java's assertQueriesReturnSimilarResults.
  def assert_queries_return_similar_results(olap, query1, query2)
    result1 = format_result(olap.execute(query1))
    result2 = format_result(olap.execute(query2))
    assert_equal measure_values(result1), measure_values(result2)
  end

  # Truncate result string to return only measure values (after first '}').
  def measure_values(result_string)
    index = result_string.index("}")
    index ? result_string[index..] : result_string
  end

  # Assert query result with currency normalization.
  # The JVM locale may produce a different currency symbol (e.g. "€")
  # than the Java tests expect ("$"). Normalize to "$" for comparison.
  def assert_query_returns_normalized(olap, mdx, expected)
    result = olap.execute(mdx)
    actual = format_result(result).gsub(/[€£¥]/, '$')
    assert_like expected, actual
  end

  # Create a connection with the non-default all member schema used by
  # testNonDefaultAllMember and testNonDefaultAllMember2.
  def connection_with_non_default_all_member
    cube_xml = <<~XML
      <Cube name="Warehouse (Default USA)">
        <Table name="inventory_fact_1997"/>
        <DimensionUsage name="Time" source="Time" foreignKey="time_id"/>
        <DimensionUsage name="Product" source="Product" foreignKey="product_id"/>
        <DimensionUsage name="Store" source="Store" foreignKey="store_id"/>
        <Dimension name="Warehouse" foreignKey="warehouse_id">
          <Hierarchy hasAll="false" defaultMember="[USA]" primaryKey="warehouse_id">
            <Table name="warehouse"/>
            <Level name="Country" column="warehouse_country" uniqueMembers="true"/>
            <Level name="State Province" column="warehouse_state_province" uniqueMembers="true"/>
            <Level name="City" column="warehouse_city" uniqueMembers="false"/>
            <Level name="Warehouse Name" column="warehouse_name" uniqueMembers="true"/>
          </Hierarchy>
        </Dimension>
        <Measure name="Warehouse Cost" column="warehouse_cost" aggregator="sum"/>
        <Measure name="Warehouse Sales" column="warehouse_sales" aggregator="sum"/>
      </Cube>
    XML

    virtual_cube_xml = <<~XML
      <VirtualCube name="Warehouse (Default USA) and Sales">
        <VirtualCubeDimension name="Product"/>
        <VirtualCubeDimension name="Store"/>
        <VirtualCubeDimension name="Time"/>
        <VirtualCubeDimension cubeName="Warehouse (Default USA)" name="Warehouse"/>
        <VirtualCubeMeasure cubeName="Sales 2" name="[Measures].[Sales Count]"/>
        <VirtualCubeMeasure cubeName="Sales 2" name="[Measures].[Store Cost]"/>
        <VirtualCubeMeasure cubeName="Sales 2" name="[Measures].[Store Sales]"/>
        <VirtualCubeMeasure cubeName="Sales 2" name="[Measures].[Unit Sales]"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Store Invoice]"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Supply Time]"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Units Ordered]"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Units Shipped]"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Warehouse Cost]"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Warehouse Sales]"/>
      </VirtualCube>
    XML

    connection_with_custom_schema(cube_xml: cube_xml, virtual_cube_xml: virtual_cube_xml)
  end

  public

  # Test case for bug MONDRIAN-163,
  # "VirtualCube SegmentArrayQuerySpec.addMeasure assert".
  # Java: VirtualCubeTest#testNoTimeDimension
  it "virtual cube without time dimension" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Sales vs Warehouse">
        <VirtualCubeDimension name="Product"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Warehouse Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Unit Sales]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      assert_query_returns olap,
        "select\n" \
        "{ [Measures].[Warehouse Sales], [Measures].[Unit Sales] }\n" \
        "ON COLUMNS,\n" \
        "{[Product].[All Products]}\n" \
        "ON ROWS\n" \
        "from [Sales vs Warehouse]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Warehouse Sales]}
          {[Measures].[Unit Sales]}
          Axis #2:
          {[Product].[All Products]}
          Row #0: 196,770.888
          Row #0: 266,773
        RESULT
    ensure
      olap.close
    end
  end

  # Java: VirtualCubeTest#testCalculatedMeasureAsDefaultMeasureInVC
  it "calculated measure as default measure in virtual cube" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Sales vs Warehouse" defaultMeasure="Profit">
        <VirtualCubeDimension name="Product"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Warehouse Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Unit Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Profit]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      assert_queries_return_similar_results(
        olap,
        "select from [Sales vs Warehouse]",
        "select from [Sales vs Warehouse] where measures.profit")
    ensure
      olap.close
    end
  end

  # Java: VirtualCubeTest#testDefaultMeasureInVCForIncorrectMeasureName
  it "default measure falls back to first measure for incorrect measure name" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Sales vs Warehouse" defaultMeasure="Profit Error">
        <VirtualCubeDimension name="Product"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Warehouse Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Unit Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Profit]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      assert_queries_return_similar_results(
        olap,
        "select from [Sales vs Warehouse]",
        "select from [Sales vs Warehouse] where measures.[Warehouse Sales]")
    ensure
      olap.close
    end
  end

  # Java: VirtualCubeTest#testVirtualCubeMeasureInvalidCubeName
  it "virtual cube measure with invalid cube name raises error" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Sales vs Warehouse">
        <VirtualCubeDimension name="Product"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Warehouse Sales]"/>
        <VirtualCubeMeasure cubeName="Bad cube" name="[Measures].[Unit Sales]"/>
      </VirtualCube>
    XML

    # Java's assertQueryThrows expects this error at query execution time, but that
    # only works because Java's TestContext.create() lazily defers schema loading until
    # the first query. In Ruby, Connection.create eagerly loads the schema, so the
    # invalid cube name error is raised during connection creation.
    error = assert_raises(Mondrian::OLAP::Error) do
      connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    end
    assert error.message.include?("Cube 'Bad cube' not found"),
      "Expected error containing 'Cube 'Bad cube' not found', got: #{error.message}"
  end

  # Java: VirtualCubeTest#testDefaultMeasureInVCForCaseSensitivity
  it "default measure in virtual cube respects case sensitivity" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Sales vs Warehouse" defaultMeasure="PROFIT">
        <VirtualCubeDimension name="Product"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Warehouse Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Unit Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Profit]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      query_without_filter = "select from [Sales vs Warehouse]"
      query_with_first_measure =
        "select from [Sales vs Warehouse] where measures.[Warehouse Sales]"
      query_with_default_measure_filter =
        "select from [Sales vs Warehouse] where measures.[Profit]"

      if Java::MondrianOlap::MondrianProperties.instance.CaseSensitive.get
        assert_queries_return_similar_results(
          olap, query_without_filter, query_with_first_measure)
      else
        assert_queries_return_similar_results(
          olap, query_without_filter, query_with_default_measure_filter)
      end
    ensure
      olap.close
    end
  end

  # Java: VirtualCubeTest#testWithTimeDimension
  it "virtual cube with time dimension" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Sales vs Warehouse">
        <VirtualCubeDimension name="Time"/>
        <VirtualCubeDimension name="Product"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Warehouse Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Unit Sales]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      assert_query_returns olap,
        "select\n" \
        "{ [Measures].[Warehouse Sales], [Measures].[Unit Sales] }\n" \
        "ON COLUMNS,\n" \
        "{[Product].[All Products]}\n" \
        "ON ROWS\n" \
        "from [Sales vs Warehouse]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Warehouse Sales]}
          {[Measures].[Unit Sales]}
          Axis #2:
          {[Product].[All Products]}
          Row #0: 196,770.888
          Row #0: 266,773
        RESULT
    ensure
      olap.close
    end
  end

  # Query a virtual cube that contains a non-conforming dimension that
  # does not have ALL as its default member.
  # Java: VirtualCubeTest#testNonDefaultAllMember
  it "non-default all member in virtual cube" do
    olap = connection_with_non_default_all_member
    begin
      assert_query_returns olap,
        "select {[Warehouse].defaultMember} on columns, " \
        "{[Measures].[Warehouse Cost]} on rows from [Warehouse (Default USA)]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Warehouse].[USA]}
          Axis #2:
          {[Measures].[Warehouse Cost]}
          Row #0: 89,043.253
        RESULT

      # There is a value for [USA] -- because it is the default member and
      # the hierarchy has no all member -- but not for [USA].[CA].
      # The Warehouse Cost for CA differs in the last decimal between databases
      # (MySQL: 25,789.087, PostgreSQL: 25,789.086) due to floating-point aggregation.
      warehouse_cost_ca = MONDRIAN_DRIVER == "postgresql" ? "25,789.086" : "25,789.087"
      assert_query_returns olap,
        "select {[Warehouse].defaultMember, [Warehouse].[USA].[CA]} on columns, " \
        "{[Measures].[Warehouse Cost], [Measures].[Sales Count]} on rows " \
        "from [Warehouse (Default USA) and Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Warehouse].[USA]}
          {[Warehouse].[USA].[CA]}
          Axis #2:
          {[Measures].[Warehouse Cost]}
          {[Measures].[Sales Count]}
          Row #0: 89,043.253
          Row #0: #{warehouse_cost_ca}
          Row #1: 86,837
          Row #1:
        RESULT
    ensure
      olap.close
    end
  end

  # Java: VirtualCubeTest#testNonDefaultAllMember2
  it "non-default all member unit sales from virtual cube" do
    olap = connection_with_non_default_all_member
    begin
      assert_query_returns olap,
        "select { measures.[unit sales] } on 0 " \
        "from [warehouse (Default USA) and Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Unit Sales]}
          Row #0: 266,773
        RESULT
    ensure
      olap.close
    end
  end

  # Java: VirtualCubeTest#testMemberVisibility
  it "member visibility in virtual cube" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Warehouse and Sales Member Visibility">
        <VirtualCubeDimension cubeName="Sales" name="Customers"/>
        <VirtualCubeDimension name="Time"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Sales Count]" visible="true" />
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Store Cost]" visible="false" />
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Store Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Profit last Period]" visible="true" />
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Units Shipped]" visible="false" />
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Average Warehouse Sale]" visible="false" />
        <CalculatedMember name="Profit" dimension="Measures" visible="false" >
          <Formula>[Measures].[Store Sales] - [Measures].[Store Cost]</Formula>
        </CalculatedMember>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      connection = olap.raw_mondrian_connection
      result = connection.execute(
        connection.parseQuery(
          "select {[Measures].[Sales Count],\n" \
          " [Measures].[Store Cost],\n" \
          " [Measures].[Store Sales],\n" \
          " [Measures].[Units Shipped],\n" \
          " [Measures].[Profit],\n" \
          " [Measures].[Profit last Period],\n" \
          " [Measures].[Average Warehouse Sale]} on columns\n" \
          "from [Warehouse and Sales Member Visibility]"))

      assert_visibility result, 0, "Sales Count", true       # explicitly visible
      assert_visibility result, 1, "Store Cost", false        # explicitly invisible
      assert_visibility result, 2, "Store Sales", true        # visible by default
      assert_visibility result, 3, "Units Shipped", false     # explicitly invisible
      assert_visibility result, 4, "Profit", false            # explicitly invisible
      assert_visibility result, 5, "Profit last Period", true # explicitly visible
      assert_visibility result, 6, "Average Warehouse Sale", false # explicitly invisible

      # Check that visibilities in the base cubes are still the same
      result = connection.execute(
        connection.parseQuery(
          "select {[Measures].[Profit last Period]} on columns from [Sales]"))
      assert_visibility result, 0, "Profit last Period", false # explicitly invisible in base cube

      result = connection.execute(
        connection.parseQuery(
          "select {[Measures].[Units Shipped],\n" \
          " [Measures].[Average Warehouse Sale]} on columns\n" \
          " from [Warehouse]"))
      assert_visibility result, 0, "Units Shipped", true           # implicitly visible in base cube
      assert_visibility result, 1, "Average Warehouse Sale", true  # implicitly visible in base cube
    ensure
      olap.close
    end
  end

  # Test an expression for the format_string of a calculated member that
  # evaluates calculated members based on a virtual cube. One cube has cache
  # turned on, the other cache turned off.
  #
  # Since evaluation of the format_string used to happen after the
  # aggregate cache was cleared, this used to fail, this should be solved
  # with the caching of the format string.
  #
  # Without caching of format string, the query returns green for all styles.
  # Java: VirtualCubeTest#testFormatStringExpressionCubeNoCache
  it "format string expression with cube that has no cache" do
    cube_xml = <<~XML
      <Cube name="Warehouse No Cache" cache="false">
        <Table name="inventory_fact_1997"/>
        <DimensionUsage name="Time" source="Time" foreignKey="time_id"/>
        <DimensionUsage name="Store" source="Store" foreignKey="store_id"/>
        <Measure name="Units Shipped" column="units_shipped" aggregator="sum" formatString="#.0"/>
      </Cube>
    XML

    virtual_cube_xml = <<~XML
      <VirtualCube name="Warehouse and Sales Format Expression Cube No Cache">
        <VirtualCubeDimension name="Store"/>
        <VirtualCubeDimension name="Time"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Store Cost]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Store Sales]"/>
        <VirtualCubeMeasure cubeName="Warehouse No Cache" name="[Measures].[Units Shipped]"/>
        <CalculatedMember name="Profit" dimension="Measures">
          <Formula>[Measures].[Store Sales] - [Measures].[Store Cost]</Formula>
        </CalculatedMember>
        <CalculatedMember name="Profit Per Unit Shipped" dimension="Measures">
          <Formula>[Measures].[Profit] / [Measures].[Units Shipped]</Formula>
          <CalculatedMemberProperty name="FORMAT_STRING" expression="IIf(([Measures].[Profit Per Unit Shipped] > 2.0), '|0.#|style=green', '|0.#|style=red')"/>
        </CalculatedMember>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(cube_xml: cube_xml, virtual_cube_xml: virtual_cube_xml)
    begin
      assert_query_returns olap,
        "select {[Measures].[Profit Per Unit Shipped]} ON COLUMNS, " \
        "{[Store].[All Stores].[USA].[CA], [Store].[All Stores].[USA].[OR], [Store].[All Stores].[USA].[WA]} ON ROWS " \
        "from [Warehouse and Sales Format Expression Cube No Cache] " \
        "where [Time].[1997]",
        <<~RESULT
          Axis #0:
          {[Time].[1997]}
          Axis #1:
          {[Measures].[Profit Per Unit Shipped]}
          Axis #2:
          {[Store].[USA].[CA]}
          {[Store].[USA].[OR]}
          {[Store].[USA].[WA]}
          Row #0: |1.6|style=red
          Row #1: |2.1|style=green
          Row #2: |1.5|style=red
        RESULT
    ensure
      olap.close
    end
  end

  # Calculated measures reference measures defined in the base cube.
  # Java: VirtualCubeTest#testCalculatedMeasure
  it "calculated measures from base cube" do
    assert_query_returns @olap,
      "select\n" \
      "{[Measures].[Profit Growth], " \
      "[Measures].[Profit], " \
      "[Measures].[Average Warehouse Sale] }\n" \
      "ON COLUMNS\n" \
      "from [Warehouse and Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Profit Growth]}
        {[Measures].[Profit]}
        {[Measures].[Average Warehouse Sale]}
        Row #0: 0.0%
        Row #0: $339,610.90
        Row #0: $2.21
      RESULT
  end

  # Java: VirtualCubeTest#testLostData
  it "does not lose data across time members" do
    assert_query_returns @olap,
      "select {[Time].[Time].Members} on columns,\n" \
      " {[Product].Children} on rows\n" \
      "from [Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997]}
        {[Time].[1997].[Q1]}
        {[Time].[1997].[Q1].[1]}
        {[Time].[1997].[Q1].[2]}
        {[Time].[1997].[Q1].[3]}
        {[Time].[1997].[Q2]}
        {[Time].[1997].[Q2].[4]}
        {[Time].[1997].[Q2].[5]}
        {[Time].[1997].[Q2].[6]}
        {[Time].[1997].[Q3]}
        {[Time].[1997].[Q3].[7]}
        {[Time].[1997].[Q3].[8]}
        {[Time].[1997].[Q3].[9]}
        {[Time].[1997].[Q4]}
        {[Time].[1997].[Q4].[10]}
        {[Time].[1997].[Q4].[11]}
        {[Time].[1997].[Q4].[12]}
        {[Time].[1998]}
        {[Time].[1998].[Q1]}
        {[Time].[1998].[Q1].[1]}
        {[Time].[1998].[Q1].[2]}
        {[Time].[1998].[Q1].[3]}
        {[Time].[1998].[Q2]}
        {[Time].[1998].[Q2].[4]}
        {[Time].[1998].[Q2].[5]}
        {[Time].[1998].[Q2].[6]}
        {[Time].[1998].[Q3]}
        {[Time].[1998].[Q3].[7]}
        {[Time].[1998].[Q3].[8]}
        {[Time].[1998].[Q3].[9]}
        {[Time].[1998].[Q4]}
        {[Time].[1998].[Q4].[10]}
        {[Time].[1998].[Q4].[11]}
        {[Time].[1998].[Q4].[12]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        Row #0: 24,597
        Row #0: 5,976
        Row #0: 1,910
        Row #0: 1,951
        Row #0: 2,115
        Row #0: 5,895
        Row #0: 1,948
        Row #0: 2,039
        Row #0: 1,908
        Row #0: 6,065
        Row #0: 2,205
        Row #0: 1,921
        Row #0: 1,939
        Row #0: 6,661
        Row #0: 1,898
        Row #0: 2,344
        Row #0: 2,419
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #0:
        Row #1: 191,940
        Row #1: 47,809
        Row #1: 15,604
        Row #1: 15,142
        Row #1: 17,063
        Row #1: 44,825
        Row #1: 14,393
        Row #1: 15,055
        Row #1: 15,377
        Row #1: 47,440
        Row #1: 17,036
        Row #1: 15,741
        Row #1: 14,663
        Row #1: 51,866
        Row #1: 14,232
        Row #1: 18,278
        Row #1: 19,356
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #1:
        Row #2: 50,236
        Row #2: 12,506
        Row #2: 4,114
        Row #2: 3,864
        Row #2: 4,528
        Row #2: 11,890
        Row #2: 3,838
        Row #2: 3,987
        Row #2: 4,065
        Row #2: 12,343
        Row #2: 4,522
        Row #2: 4,035
        Row #2: 3,786
        Row #2: 13,497
        Row #2: 3,828
        Row #2: 4,648
        Row #2: 5,021
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
        Row #2:
      RESULT

    assert_query_returns @olap,
      "select\n" \
      " {[Measures].[Unit Sales]} on 0,\n" \
      " {[Product].Children} on 1\n" \
      "from [Warehouse and Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        Row #0: 24,597
        Row #1: 191,940
        Row #2: 50,236
      RESULT
  end

  # Tests a calc measure which combines measures from the Sales cube with
  # measures from the Warehouse cube.
  # Java: VirtualCubeTest#testCalculatedMeasureAcrossCubes
  it "calculated measure across cubes" do
    assert_query_returns @olap,
      "with member [Measures].[Shipped per Ordered] as ' [Measures].[Units Shipped] / [Measures].[Unit Sales] ', format_string='#.00%'\n" \
      " member [Measures].[Profit per Unit Shipped] as ' [Measures].[Profit] / [Measures].[Units Shipped] '\n" \
      "select\n" \
      " {[Measures].[Unit Sales], \n" \
      "  [Measures].[Units Shipped],\n" \
      "  [Measures].[Shipped per Ordered],\n" \
      "  [Measures].[Profit per Unit Shipped]} on 0,\n" \
      " NON EMPTY Crossjoin([Product].Children, [Time].[1997].Children) on 1\n" \
      "from [Warehouse and Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Units Shipped]}
        {[Measures].[Shipped per Ordered]}
        {[Measures].[Profit per Unit Shipped]}
        Axis #2:
        {[Product].[Drink], [Time].[1997].[Q1]}
        {[Product].[Drink], [Time].[1997].[Q2]}
        {[Product].[Drink], [Time].[1997].[Q3]}
        {[Product].[Drink], [Time].[1997].[Q4]}
        {[Product].[Food], [Time].[1997].[Q1]}
        {[Product].[Food], [Time].[1997].[Q2]}
        {[Product].[Food], [Time].[1997].[Q3]}
        {[Product].[Food], [Time].[1997].[Q4]}
        {[Product].[Non-Consumable], [Time].[1997].[Q1]}
        {[Product].[Non-Consumable], [Time].[1997].[Q2]}
        {[Product].[Non-Consumable], [Time].[1997].[Q3]}
        {[Product].[Non-Consumable], [Time].[1997].[Q4]}
        Row #0: 5,976
        Row #0: 4637.0
        Row #0: 77.59%
        Row #0: $1.50
        Row #1: 5,895
        Row #1: 4501.0
        Row #1: 76.35%
        Row #1: $1.60
        Row #2: 6,065
        Row #2: 6258.0
        Row #2: 103.18%
        Row #2: $1.15
        Row #3: 6,661
        Row #3: 5802.0
        Row #3: 87.10%
        Row #3: $1.38
        Row #4: 47,809
        Row #4: 37153.0
        Row #4: 77.71%
        Row #4: $1.64
        Row #5: 44,825
        Row #5: 35459.0
        Row #5: 79.11%
        Row #5: $1.62
        Row #6: 47,440
        Row #6: 41545.0
        Row #6: 87.57%
        Row #6: $1.47
        Row #7: 51,866
        Row #7: 34706.0
        Row #7: 66.91%
        Row #7: $1.91
        Row #8: 12,506
        Row #8: 9161.0
        Row #8: 73.25%
        Row #8: $1.76
        Row #9: 11,890
        Row #9: 9227.0
        Row #9: 77.60%
        Row #9: $1.65
        Row #10: 12,343
        Row #10: 9986.0
        Row #10: 80.90%
        Row #10: $1.59
        Row #11: 13,497
        Row #11: 9291.0
        Row #11: 68.84%
        Row #11: $1.86
      RESULT
  end

  # Tests a calc member defined in the cube.
  # Java: VirtualCubeTest#testCalculatedMemberInSchema
  it "calculated member defined in schema" do
    olap = connection_with_modified_cube("Warehouse and Sales",
      calculated_members: <<~XML
        <CalculatedMember name="Shipped per Ordered" dimension="Measures">
          <Formula>[Measures].[Units Shipped] / [Measures].[Unit Sales]</Formula>
          <CalculatedMemberProperty name="FORMAT_STRING" value="#.0%"/>
        </CalculatedMember>
      XML
    )
    begin
      assert_query_returns olap,
        "select\n" \
        " {[Measures].[Unit Sales], \n" \
        "  [Measures].[Shipped per Ordered]} on 0,\n" \
        " NON EMPTY Crossjoin([Product].Children, [Time].[1997].Children) on 1\n" \
        "from [Warehouse and Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Shipped per Ordered]}
          Axis #2:
          {[Product].[Drink], [Time].[1997].[Q1]}
          {[Product].[Drink], [Time].[1997].[Q2]}
          {[Product].[Drink], [Time].[1997].[Q3]}
          {[Product].[Drink], [Time].[1997].[Q4]}
          {[Product].[Food], [Time].[1997].[Q1]}
          {[Product].[Food], [Time].[1997].[Q2]}
          {[Product].[Food], [Time].[1997].[Q3]}
          {[Product].[Food], [Time].[1997].[Q4]}
          {[Product].[Non-Consumable], [Time].[1997].[Q1]}
          {[Product].[Non-Consumable], [Time].[1997].[Q2]}
          {[Product].[Non-Consumable], [Time].[1997].[Q3]}
          {[Product].[Non-Consumable], [Time].[1997].[Q4]}
          Row #0: 5,976
          Row #0: 77.6%
          Row #1: 5,895
          Row #1: 76.4%
          Row #2: 6,065
          Row #2: 103.2%
          Row #3: 6,661
          Row #3: 87.1%
          Row #4: 47,809
          Row #4: 77.7%
          Row #5: 44,825
          Row #5: 79.1%
          Row #6: 47,440
          Row #6: 87.6%
          Row #7: 51,866
          Row #7: 66.9%
          Row #8: 12,506
          Row #8: 73.3%
          Row #9: 11,890
          Row #9: 77.6%
          Row #10: 12,343
          Row #10: 80.9%
          Row #11: 13,497
          Row #11: 68.8%
        RESULT
    ensure
      olap.close
    end
  end

  # Result should exclude measures that are not explicitly defined
  # in the virtual cube (e.g., [Profit last Period]).
  # Java: VirtualCubeTest#testAllMeasureMembers
  it "allMembers returns only explicitly defined measures" do
    assert_query_returns @olap,
      "select\n" \
      "{[Measures].allMembers} on columns\n" \
      "from [Warehouse and Sales]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Sales Count]}
        {[Measures].[Store Cost]}
        {[Measures].[Store Sales]}
        {[Measures].[Unit Sales]}
        {[Measures].[Store Invoice]}
        {[Measures].[Supply Time]}
        {[Measures].[Units Ordered]}
        {[Measures].[Units Shipped]}
        {[Measures].[Warehouse Cost]}
        {[Measures].[Warehouse Profit]}
        {[Measures].[Warehouse Sales]}
        {[Measures].[Profit]}
        {[Measures].[Profit Growth]}
        {[Measures].[Average Warehouse Sale]}
        {[Measures].[Profit Per Unit Shipped]}
        Row #0: 86,837
        Row #0: 225,627.23
        Row #0: 565,238.13
        Row #0: 266,773
        Row #0: 102,278.409
        Row #0: 10,425
        Row #0: 227238.0
        Row #0: 207726.0
        Row #0: 89,043.253
        Row #0: 107,727.635
        Row #0: 196,770.888
        Row #0: $339,610.90
        Row #0: 0.0%
        Row #0: $2.21
        Row #0: $1.63
      RESULT
  end

  # Test a virtual cube where one of the dimensions contains an ordinalColumn property.
  # Java: VirtualCubeTest#testOrdinalColumn
  it "ordinal column in virtual cube dimension" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Sales vs HR">
        <VirtualCubeDimension name="Store"/>
        <VirtualCubeDimension cubeName="HR" name="Position"/>
        <VirtualCubeMeasure cubeName="HR" name="[Measures].[Org Salary]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      assert_query_returns_normalized olap,
        "select {[Measures].[Org Salary]} on columns, " \
        "non empty " \
        "crossjoin([Store].[Store Country].members, [Position].[Store Management].children) " \
        "on rows from [Sales vs HR]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Org Salary]}
          Axis #2:
          {[Store].[Canada], [Position].[Store Management].[Store Manager]}
          {[Store].[Canada], [Position].[Store Management].[Store Assistant Manager]}
          {[Store].[Canada], [Position].[Store Management].[Store Shift Supervisor]}
          {[Store].[Mexico], [Position].[Store Management].[Store Manager]}
          {[Store].[Mexico], [Position].[Store Management].[Store Assistant Manager]}
          {[Store].[Mexico], [Position].[Store Management].[Store Shift Supervisor]}
          {[Store].[USA], [Position].[Store Management].[Store Manager]}
          {[Store].[USA], [Position].[Store Management].[Store Assistant Manager]}
          {[Store].[USA], [Position].[Store Management].[Store Shift Supervisor]}
          Row #0: $462.86
          Row #1: $394.29
          Row #2: $565.71
          Row #3: $13,254.55
          Row #4: $11,443.64
          Row #5: $17,705.46
          Row #6: $4,069.80
          Row #7: $3,417.72
          Row #8: $5,145.96
        RESULT
    ensure
      olap.close
    end
  end

  # Java: VirtualCubeTest#testDefaultMeasureProperty
  it "default measure property selects correct default" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Sales vs Warehouse" defaultMeasure="Unit Sales">
        <VirtualCubeDimension name="Product"/>
        <VirtualCubeMeasure cubeName="Warehouse" name="[Measures].[Warehouse Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Unit Sales]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Profit]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      assert_queries_return_similar_results(
        olap,
        "select from [Sales vs Warehouse]",
        "select from [Sales vs Warehouse] where measures.[Unit Sales]")
    ensure
      olap.close
    end
  end

  # Checks that native set caching considers base cubes in the cache key.
  # Native sets referencing different base cubes do not share the cached result.
  # This test only runs on Derby in Java; skip for all other databases.
  # Java: VirtualCubeTest#testNativeSetCaching
  it "native set caching differentiates base cubes" do
    skip "Java test is Derby-only; skipped for #{MONDRIAN_DRIVER}"
  end

  # Test case for bug MONDRIAN-322,
  # "cube.getStar() throws NullPointerException".
  # Happens when you aggregate distinct-count measures in a virtual cube.
  # Java: VirtualCubeTest#testBugMondrian322
  it "bug MONDRIAN-322 aggregate distinct-count in virtual cube" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Warehouse and Sales2" defaultMeasure="Store Sales">
        <VirtualCubeDimension cubeName="Sales" name="Customers"/>
        <VirtualCubeDimension name="Time"/>
        <VirtualCubeDimension cubeName="Warehouse" name="Warehouse"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Customer Count]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Store Sales]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      # This test case does not actually reject the dimension constraint from
      # an unrelated base cube. The reason is that the constraint contains an
      # AllLevel member. Even though semantically constraining Cells using a
      # non-existent dimension perhaps does not make sense; however, in the
      # case where the constraint contains AllLevel member, the constraint
      # can be considered "always true".
      #
      # See the next test case for a constraint that does not contain
      # AllLevel member and hence cannot be satisfied. The cell should be empty.
      assert_query_returns olap,
        "with member [Warehouse].[x] as 'Aggregate([Warehouse].members)'\n" \
        "member [Measures].[foo] AS '([Warehouse].[x],[Measures].[Customer Count])'\n" \
        "select {[Measures].[foo]} on 0 from [Warehouse And Sales2]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[foo]}
          Row #0: 5,581
        RESULT
    ensure
      olap.close
    end
  end

  # Java: VirtualCubeTest#testBugMondrian322a
  it "bug MONDRIAN-322a non-all member constraint returns empty cell" do
    virtual_cube_xml = <<~XML
      <VirtualCube name="Warehouse and Sales2" defaultMeasure="Store Sales">
        <VirtualCubeDimension cubeName="Sales" name="Customers"/>
        <VirtualCubeDimension name="Time"/>
        <VirtualCubeDimension cubeName="Warehouse" name="Warehouse"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Customer Count]"/>
        <VirtualCubeMeasure cubeName="Sales" name="[Measures].[Store Sales]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(virtual_cube_xml: virtual_cube_xml)
    begin
      assert_query_returns olap,
        "with member [Warehouse].[x] as 'Aggregate({[Warehouse].[Canada], [Warehouse].[USA]})'\n" \
        "member [Measures].[foo] AS '([Warehouse].[x],[Measures].[Customer Count])'\n" \
        "select {[Measures].[foo]} on 0 from [Warehouse And Sales2]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[foo]}
          Row #0:
        RESULT
    ensure
      olap.close
    end
  end

  # Test case for bug MONDRIAN-352,
  # "Caption is not set on RolapVirtualCubeMeasure".
  # Java: VirtualCubeTest#testVirtualCubeMeasureCaption
  it "virtual cube measure caption is preserved" do
    cube_xml = <<~XML
      <Cube name="TestStore">
        <Table name="store"/>
        <Dimension name="HCB" caption="Has coffee bar caption">
          <Hierarchy hasAll="true">
            <Level name="Has coffee bar" column="coffee_bar" uniqueMembers="true" type="Boolean"/>
          </Hierarchy>
        </Dimension>
        <Measure name="Store Sqft" caption="Store Sqft Caption" column="store_sqft" aggregator="sum" formatString="#,###"/>
      </Cube>
    XML

    virtual_cube_xml = <<~XML
      <VirtualCube name="VirtualTestStore">
        <VirtualCubeDimension cubeName="TestStore" name="HCB"/>
        <VirtualCubeMeasure cubeName="TestStore" name="[Measures].[Store Sqft]"/>
      </VirtualCube>
    XML

    olap = connection_with_custom_schema(cube_xml: cube_xml, virtual_cube_xml: virtual_cube_xml)
    begin
      connection = olap.raw_mondrian_connection
      result = connection.execute(
        connection.parseQuery(
          "select {[Measures].[Store Sqft]} ON COLUMNS," \
          "{[HCB]} ON ROWS " \
          "from [VirtualTestStore]"))

      axes = result.getAxes
      positions = axes[0].getPositions
      member = positions.get(0).get(0)
      assert_equal "Store Sqft Caption", member.getCaption
    ensure
      olap.close
    end
  end

  # Test that RolapCubeLevel is used correctly in the context of virtual cube.
  # Java: VirtualCubeTest#testRolapCubeLevelInVirtualCube
  it "RolapCubeLevel in virtual cube with filter" do
    query1 =
      "With " \
      "Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Warehouse],[*BASE_MEMBERS_Time])' " \
      "Set [*NATIVE_MEMBERS_Warehouse] as 'Generate([*NATIVE_CJ_SET], {[Warehouse].CurrentMember})' " \
      "Set [*BASE_MEMBERS_Warehouse] as '[Warehouse].[Country].Members' " \
      "Set [*NATIVE_MEMBERS_Time] as 'Generate([*NATIVE_CJ_SET], {[Time].[Time].CurrentMember})' " \
      "Set [*BASE_MEMBERS_Time] as '[Time].[Month].Members' " \
      "Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}' Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Warehouse Sales]', FORMAT_STRING = '#,##0', SOLVE_ORDER=400 " \
      "Select [*BASE_MEMBERS_Measures] on columns, Non Empty Generate([*NATIVE_CJ_SET], {([Warehouse].currentMember,[Time].[Time].currentMember)}) on rows From [Warehouse and Sales] "

    query2 =
      "With " \
      "Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Warehouse],[*BASE_MEMBERS_Time])' " \
      "Set [*NATIVE_MEMBERS_Warehouse] as 'Generate([*NATIVE_CJ_SET], {[Warehouse].CurrentMember})' " \
      "Set [*BASE_MEMBERS_Warehouse] as '[Warehouse].[Country].Members' " \
      "Set [*NATIVE_MEMBERS_Time] as 'Generate([*NATIVE_CJ_SET], {[Time].[Time].CurrentMember})' " \
      "Set [*BASE_MEMBERS_Time] as 'Filter([Time].[Month].Members,[Time].[Time].CurrentMember Not In {[Time].[1997].[Q1].[2]})' " \
      "Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}' Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Warehouse Sales]', FORMAT_STRING = '#,##0', SOLVE_ORDER=400 " \
      "Select [*BASE_MEMBERS_Measures] on columns, Non Empty Generate([*NATIVE_CJ_SET], {([Warehouse].currentMember,[Time].[Time].currentMember)}) on rows From [Warehouse and Sales]"

    @olap.execute(query1)

    # The query with the filter should now succeed without NPE
    assert_query_returns @olap, query2,
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[*FORMATTED_MEASURE_0]}
        Axis #2:
        {[Warehouse].[USA], [Time].[1997].[Q1].[1]}
        {[Warehouse].[USA], [Time].[1997].[Q1].[3]}
        {[Warehouse].[USA], [Time].[1997].[Q2].[4]}
        {[Warehouse].[USA], [Time].[1997].[Q2].[5]}
        {[Warehouse].[USA], [Time].[1997].[Q2].[6]}
        {[Warehouse].[USA], [Time].[1997].[Q3].[7]}
        {[Warehouse].[USA], [Time].[1997].[Q3].[8]}
        {[Warehouse].[USA], [Time].[1997].[Q3].[9]}
        {[Warehouse].[USA], [Time].[1997].[Q4].[10]}
        {[Warehouse].[USA], [Time].[1997].[Q4].[11]}
        {[Warehouse].[USA], [Time].[1997].[Q4].[12]}
        Row #0: 21,762
        Row #1: 13,775
        Row #2: 15,938
        Row #3: 15,649
        Row #4: 14,629
        Row #5: 18,626
        Row #6: 15,833
        Row #7: 21,393
        Row #8: 17,100
        Row #9: 15,356
        Row #10: 13,948
      RESULT
  end

  # Tests that the logic to apply non empty context constraint in virtual
  # cube is correct. The joins should not be cartesian product.
  # Known Java-side failure (SQL pattern assertion); test result only.
  # Java: VirtualCubeTest#testNonEmptyCJConstraintOnVirtualCube
  it "non-empty crossjoin constraint on virtual cube" do
    skip unless mondrian_property(:EnableNativeCrossJoin).get

    with_properties(GenerateFormattedSql: true) do
      query =
        "with " \
        "set [foo] as [Time].[Month].members " \
        "set [bar] as {[Store].[USA]} " \
        "Select {[Measures].[Warehouse Sales],[Measures].[Store Sales]} on columns, " \
        "nonemptycrossjoin([foo],[bar]) on rows " \
        "From [Warehouse and Sales] " \
        "Where ([Product].[All Products].[Food])"

      assert_query_returns @olap, query,
        <<~RESULT
          Axis #0:
          {[Product].[Food]}
          Axis #1:
          {[Measures].[Warehouse Sales]}
          {[Measures].[Store Sales]}
          Axis #2:
          {[Time].[1997].[Q1].[1], [Store].[USA]}
          {[Time].[1997].[Q1].[2], [Store].[USA]}
          {[Time].[1997].[Q1].[3], [Store].[USA]}
          {[Time].[1997].[Q2].[4], [Store].[USA]}
          {[Time].[1997].[Q2].[5], [Store].[USA]}
          {[Time].[1997].[Q2].[6], [Store].[USA]}
          {[Time].[1997].[Q3].[7], [Store].[USA]}
          {[Time].[1997].[Q3].[8], [Store].[USA]}
          {[Time].[1997].[Q3].[9], [Store].[USA]}
          {[Time].[1997].[Q4].[10], [Store].[USA]}
          {[Time].[1997].[Q4].[11], [Store].[USA]}
          {[Time].[1997].[Q4].[12], [Store].[USA]}
          Row #0: 16,083.015
          Row #0: 32,993.12
          Row #1: 9,298.379
          Row #1: 32,139.91
          Row #2: 10,129.659
          Row #2: 36,128.29
          Row #3: 11,415.462
          Row #3: 30,747.21
          Row #4: 11,358.086
          Row #4: 31,896.24
          Row #5: 10,425.768
          Row #5: 32,792.55
          Row #6: 13,684.193
          Row #6: 36,324.76
          Row #7: 11,332.797
          Row #7: 33,842.75
          Row #8: 15,667.978
          Row #8: 31,640.09
          Row #9: 11,902.18
          Row #9: 30,337.12
          Row #10: 10,144.841
          Row #10: 38,709.15
          Row #11: 9,705.561
          Row #11: 41,484.40
        RESULT
    end
  end

  # Tests that the logic to apply non empty context constraint in virtual
  # cube is correct. The joins should not be cartesian product.
  # Known Java-side failure (SQL pattern assertion); test result only.
  # Java: VirtualCubeTest#testNonEmptyConstraintOnVirtualCubeWithCalcMeasure
  it "non-empty constraint on virtual cube with calculated measure" do
    skip unless mondrian_property(:EnableNativeNonEmpty).get

    with_properties(LevelPreCacheThreshold: 0, GenerateFormattedSql: true) do
      query =
        "with " \
        "set [bar] as {[Store].[USA]} " \
        "member [Measures].[CalcMeasure] as '[Measures].[Warehouse Sales] / [Measures].[Store Sales]' " \
        "Select " \
        "{[Measures].[CalcMeasure]} on columns, " \
        "non empty([Product].[Product Family].Members) on rows " \
        "From [Warehouse and Sales] " \
        "where [bar]"

      assert_query_returns @olap, query,
        <<~RESULT
          Axis #0:
          {[Store].[USA]}
          Axis #1:
          {[Measures].[CalcMeasure]}
          Axis #2:
          {[Product].[Drink]}
          {[Product].[Food]}
          {[Product].[Non-Consumable]}
          Row #0: 0.369
          Row #1: 0.345
          Row #2: 0.35
        RESULT
    end
  end

  # Test case for bug MONDRIAN-902,
  # "mondrian populating the same members on both axes".
  # Java: VirtualCubeTest#testBugMondrian902
  it "bug MONDRIAN-902 different members on each axis" do
    connection = @olap.raw_mondrian_connection
    result = connection.execute(
      connection.parseQuery(
        "SELECT\n" \
        "NON EMPTY CrossJoin(\n" \
        "  [Education Level].[Education Level].Members,\n" \
        "  CrossJoin(\n" \
        "    [Product].[Product Family].Members,\n" \
        "    [Store].[Store State].Members)) ON COLUMNS,\n" \
        "NON EMPTY CrossJoin(\n" \
        "  [Promotions].[Promotion Name].Members,\n" \
        "  [Marital Status].[Marital Status].Members) ON ROWS\n" \
        "FROM [Warehouse and Sales]"))

    assert_equal(
      "[[Education Level].[Bachelors Degree], [Product].[Drink], [Store].[USA].[CA]]",
      result.getAxes[0].getPositions.get(0).toString)
    assert_equal 45, result.getAxes[0].getPositions.size
    # With bug MONDRIAN-902, this gave the same result as for axis #0:
    assert_equal(
      "[[Promotions].[Bag Stuffers], [Marital Status].[M]]",
      result.getAxes[1].getPositions.get(0).toString)
    assert_equal 96, result.getAxes[1].getPositions.size
  end

  # MONDRIAN-1061
  # The idea is that [recurse] is a calculated member that uses
  # CoalesceEmpty((Measures.[Unit Sales], [Time].CurrentMember),
  # (Measures.[recurse],[Time].CurrentMember.PrevMember)))
  # FoodMart has no data for 1998 quarters, so we expect:
  # - not to fall into StackOverflow for recursive calculation when member
  #   is referenced in VirtualCube.
  # - check that CoalesceEmpty calculated correctly (repeatable values from
  #   previous not null result)
  # Java: VirtualCubeTest#testVirtualCubeRecursiveMember
  it "virtual cube recursive member" do
    schema = <<~SCHEMA
      <Schema name="FoodMart">
      <Dimension type="TimeDimension" highCardinality="false" name="Time">
      <Hierarchy visible="true" hasAll="false" primaryKey="time_id">
      <Table name="time_by_day"/>
      <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true" levelType="TimeYears"/>
      <Level name="Quarter" column="quarter" type="String" uniqueMembers="false" levelType="TimeQuarters"/>
      </Hierarchy>
      </Dimension>
      <Cube name="Sales" visible="true" defaultMeasure="Unit Sales">
      <Table name="sales_fact_1997">
      <AggName name="agg_c_special_sales_fact_1997">
      <AggFactCount column="FACT_COUNT"/>
      <AggMeasure column="UNIT_SALES_SUM" name="[Measures].[Unit Sales]"/>
      <AggLevel column="TIME_YEAR" name="[Time].[Year]"/>
      </AggName>
      </Table>
      <DimensionUsage source="Time" name="Time" foreignKey="time_id" highCardinality="false"/>
      <Measure name="Unit Sales" column="unit_sales" aggregator="sum"/>
      <CalculatedMember name="recurse" dimension="Measures" visible="true">
      <Formula><![CDATA[(CoalesceEmpty((Measures.[Unit Sales], [Time].CurrentMember ) ,(Measures.[recurse],[Time].CurrentMember.PrevMember)))]]></Formula>
      </CalculatedMember>
      </Cube>
      <VirtualCube enabled="true" name="Warehouse and Sales" defaultMeasure="Store Sales" visible="true">
      <VirtualCubeDimension visible="true" highCardinality="false" name="Time"/>
      <VirtualCubeMeasure cubeName="Sales" name="[Measures].[recurse]" visible="true"/>
      </VirtualCube>
      </Schema>
    SCHEMA

    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    olap = Mondrian::OLAP::Connection.create(params)
    begin
      assert_query_returns olap,
        "SELECT {[Time].[1998].Children} on columns," \
        " {[recurse]} on rows " \
        "FROM [Warehouse and Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Time].[1998].[Q1]}
          {[Time].[1998].[Q2]}
          {[Time].[1998].[Q3]}
          {[Time].[1998].[Q4]}
          Axis #2:
          {[Measures].[recurse]}
          Row #0: 72,024
          Row #0: 72,024
          Row #0: 72,024
          Row #0: 72,024
        RESULT
    ensure
      olap.close
    end
  end

  # Java: VirtualCubeTest#testCrossjoinOptimizerWithVirtualCube
  it "crossjoin optimizer with virtual cube" do
    olap = connection_with_modified_cube("Warehouse and Sales",
      measures: '<VirtualCubeMeasure cubeName="Sales" name="[Measures].[Customer Count]"/>'
    )
    begin
      assert_query_returns olap,
        "WITH member measures.ratio as 'measures.[Store Cost]/measures.[warehouse cost]' " \
        " member [marital status].agg as 'aggregate({[marital status].M})' " \
        " select non empty [Warehouse].[USA] " \
        " * {[marital status].[marital status].members, [marital status].agg }  on 0 " \
        "FROM [warehouse and sales] where [measures].[Customer Count]",
        <<~RESULT
          Axis #0:
          {[Measures].[Customer Count]}
          Axis #1:
        RESULT
    ensure
      olap.close
    end
  end

  private

  # Assert visibility of a measure in a result at a given ordinal position.
  def assert_visibility(result, ordinal, expected_name, expected_visibility)
    column_positions = result.getAxes[0].getPositions
    measure = column_positions.get(ordinal).get(0)
    assert_equal expected_name, measure.getName
    assert_equal expected_visibility,
      measure.getPropertyValue(Java::MondrianOlap::Property::VISIBLE.name)
  end
end
