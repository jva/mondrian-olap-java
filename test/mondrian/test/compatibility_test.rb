# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2005-2005 SAS Institute, Inc.
# Copyright (C) 2006-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/test/CompatibilityTest.java
describe "Compatibility" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Assert that an axis expression wrapped in "select {expr} on columns from Sales"
  # raises an error whose message contains the pattern.
  # Mirrors Java's assertAxisThrows.
  def assert_axis_throws(olap, expression, pattern, cube: "Sales")
    mdx = "SELECT {#{expression}} ON COLUMNS FROM #{cube}"
    error = assert_raises(Mondrian::OLAP::Error) { olap.execute(mdx) }
    full_message = error.message
    cause = error
    cause = cause.cause while cause.cause && cause.cause != cause
    full_message = "#{full_message} #{cause.message}" if cause != error
    assert full_message.include?(pattern),
      "Expected error containing '#{pattern}', got: #{full_message}"
  end

  # Execute a singleton axis expression and return the member's unique name.
  # Mirrors Java's executeSingletonAxis which returns Member.toString().
  def execute_singleton_axis(olap, expression, cube: "Sales")
    mdx = "SELECT {#{expression}} ON COLUMNS FROM [#{cube}]"
    cell_set = olap.execute(mdx).raw_cell_set
    axis = cell_set.getAxes.get(0)
    positions = axis.getPositions
    case positions.size
    when 0
      nil
    when 1
      position = positions.get(0)
      position.getMembers.get(0).getUniqueName
    else
      raise "Expression #{expression} yielded #{positions.size} positions"
    end
  end

  # Check that an axis expression resolves to the expected member.
  # Mirrors Java's checkAxis(result, expression).
  def check_axis(olap, expected, expression)
    actual = execute_singleton_axis(olap, expression)
    assert_equal expected, actual
  end

  # Helper to create a connection with a new cube added to the schema.
  def connection_with_new_cube(cube_xml)
    schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  # Check whether the null member representation is the default "#null".
  def default_null_member_representation?
    Java::MondrianOlap::MondrianProperties.instance.NullMemberRepresentation.get == "#null"
  end

  describe "cube names" do
    # Java: CompatibilityTest#testCubeCase
    it "cube names are case insensitive" do
      query_from = "SELECT {[Measures].[Unit Sales]} ON COLUMNS FROM "
      expected = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Row #0: 266,773
      RESULT

      assert_query_returns @olap, query_from + "[Sales]", expected
      assert_query_returns @olap, query_from + "[SALES]", expected
      assert_query_returns @olap, query_from + "[sAlEs]", expected
      assert_query_returns @olap, query_from + "[sales]", expected
    end

    # Java: CompatibilityTest#testCubeBrackets
    it "brackets around cube names are optional" do
      query_from = "SELECT {[Measures].[Unit Sales]} ON COLUMNS FROM "
      expected = <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Row #0: 266,773
      RESULT

      assert_query_returns @olap, query_from + "Sales", expected
      assert_query_returns @olap, query_from + "SALES", expected
      assert_query_returns @olap, query_from + "sAlEs", expected
      assert_query_returns @olap, query_from + "sales", expected
    end
  end

  # Java: CompatibilityTest#testReservedWord
  it "diagnoses reserved words" do
    # Java's assertAxisThrows wraps the expression in "select {expr} on columns from Sales",
    # which produces a syntax error because 'ordinal' is a reserved word.
    assert_axis_throws @olap,
      "with member [Measures].ordinal as '1' select {[Measures].ordinal} on columns from Sales",
      "Syntax error"

    # Quoted reserved word should work
    assert_query_returns @olap,
      "WITH MEMBER [Measures].[ordinal] AS '1' SELECT {[Measures].[ordinal]} ON COLUMNS FROM Sales",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[ordinal]}
        Row #0: 1
      RESULT
  end

  describe "dimension names" do
    # Java: CompatibilityTest#testDimensionCase
    it "dimension names are case insensitive" do
      check_axis @olap, "[Measures].[Unit Sales]", "[Measures].[Unit Sales]"
      check_axis @olap, "[Measures].[Unit Sales]", "[MEASURES].[Unit Sales]"
      check_axis @olap, "[Measures].[Unit Sales]", "[mEaSuReS].[Unit Sales]"
      check_axis @olap, "[Measures].[Unit Sales]", "[measures].[Unit Sales]"

      check_axis @olap, "[Customers].[All Customers]", "[Customers].[All Customers]"
      check_axis @olap, "[Customers].[All Customers]", "[CUSTOMERS].[All Customers]"
      check_axis @olap, "[Customers].[All Customers]", "[cUsToMeRs].[All Customers]"
      check_axis @olap, "[Customers].[All Customers]", "[customers].[All Customers]"
    end

    # Java: CompatibilityTest#testDimensionBrackets
    it "brackets around dimension names are optional" do
      check_axis @olap, "[Measures].[Unit Sales]", "Measures.[Unit Sales]"
      check_axis @olap, "[Measures].[Unit Sales]", "MEASURES.[Unit Sales]"
      check_axis @olap, "[Measures].[Unit Sales]", "mEaSuReS.[Unit Sales]"
      check_axis @olap, "[Measures].[Unit Sales]", "measures.[Unit Sales]"

      check_axis @olap, "[Customers].[All Customers]", "Customers.[All Customers]"
      check_axis @olap, "[Customers].[All Customers]", "CUSTOMERS.[All Customers]"
      check_axis @olap, "[Customers].[All Customers]", "cUsToMeRs.[All Customers]"
      check_axis @olap, "[Customers].[All Customers]", "customers.[All Customers]"
    end
  end

  describe "member names" do
    # Java: CompatibilityTest#testMemberCase
    it "member names are case insensitive" do
      check_axis @olap, "[Measures].[Unit Sales]", "[Measures].[UNIT SALES]"
      check_axis @olap, "[Measures].[Unit Sales]", "[Measures].[uNiT sAlEs]"
      check_axis @olap, "[Measures].[Unit Sales]", "[Measures].[unit sales]"

      check_axis @olap, "[Measures].[Profit]", "[Measures].[Profit]"
      check_axis @olap, "[Measures].[Profit]", "[Measures].[pRoFiT]"
      check_axis @olap, "[Measures].[Profit]", "[Measures].[PROFIT]"
      check_axis @olap, "[Measures].[Profit]", "[Measures].[profit]"

      check_axis @olap, "[Customers].[All Customers]", "[Customers].[All Customers]"
      check_axis @olap, "[Customers].[All Customers]", "[Customers].[ALL CUSTOMERS]"
      check_axis @olap, "[Customers].[All Customers]", "[Customers].[aLl CuStOmErS]"
      check_axis @olap, "[Customers].[All Customers]", "[Customers].[all customers]"

      check_axis @olap, "[Customers].[Mexico]", "[Customers].[Mexico]"
      check_axis @olap, "[Customers].[Mexico]", "[Customers].[MEXICO]"
      check_axis @olap, "[Customers].[Mexico]", "[Customers].[mExIcO]"
      check_axis @olap, "[Customers].[Mexico]", "[Customers].[mexico]"
    end

    # Java: CompatibilityTest#testMemberBrackets
    it "brackets around member names are optional" do
      check_axis @olap, "[Measures].[Profit]", "[Measures].Profit"
      check_axis @olap, "[Measures].[Profit]", "[Measures].pRoFiT"
      check_axis @olap, "[Measures].[Profit]", "[Measures].PROFIT"
      check_axis @olap, "[Measures].[Profit]", "[Measures].profit"

      check_axis @olap, "[Customers].[Mexico]", "[Customers].Mexico"
      check_axis @olap, "[Customers].[Mexico]", "[Customers].MEXICO"
      check_axis @olap, "[Customers].[Mexico]", "[Customers].mExIcO"
      check_axis @olap, "[Customers].[Mexico]", "[Customers].mexico"
    end
  end

  # Java: CompatibilityTest#testCalculatedMemberCase
  it "calculated member names are case insensitive" do
    with_properties(CaseSensitive: false) do
      assert_query_returns @olap,
        "WITH MEMBER [Measures].[CaLc] AS '1' SELECT {[Measures].[CaLc]} ON COLUMNS FROM Sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[CaLc]}
          Row #0: 1
        RESULT

      assert_query_returns @olap,
        "WITH MEMBER [Measures].[CaLc] AS '1' SELECT {[Measures].[cAlC]} ON COLUMNS FROM Sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[CaLc]}
          Row #0: 1
        RESULT

      assert_query_returns @olap,
        "WITH MEMBER [mEaSuReS].[CaLc] AS '1' SELECT {[MeAsUrEs].[cAlC]} ON COLUMNS FROM Sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[CaLc]}
          Row #0: 1
        RESULT
    end
  end

  # Java: CompatibilityTest#testSolveOrderCase
  it "solve order keyword is case insensitive" do
    expected = <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Product].[ProdCalc]}
      Axis #2:
      {[Store].[StoreCalc]}
      Row #0: 1
    RESULT

    %w[SOLVE_ORDER SoLvE_OrDeR solve_order].each do |keyword|
      mdx = <<~MDX
        WITH
           MEMBER [Store].[StoreCalc] AS '0', #{keyword}=0
           MEMBER [Product].[ProdCalc] AS '1', #{keyword}=1
        SELECT
           { [Product].[ProdCalc] } ON COLUMNS,
           { [Store].[StoreCalc] } ON ROWS
        FROM Sales
      MDX
      assert_query_returns @olap, mdx, expected
    end
  end

  # Java: CompatibilityTest#testHierarchyNames
  it "hierarchy names are accepted in various forms" do
    check_axis @olap, "[Customers].[All Customers]", "[Customers].[All Customers]"
    check_axis @olap, "[Customers].[All Customers]", "[Customers].[Customers].[All Customers]"
    check_axis @olap, "[Customers].[All Customers]", "Customers.[Customers].[All Customers]"
    check_axis @olap, "[Customers].[All Customers]", "[Customers].Customers.[All Customers]"
  end

  # Java: CompatibilityTest#testCaseInsensitiveNullMember
  it "null member on String hierarchy level can be looked up case insensitively" do
    skip "Non-default null member representation" unless default_null_member_representation?

    cube_xml = <<~XML
      <Cube name="Sales_inline">
        <Table name="sales_fact_1997"/>
        <DimensionUsage name="Time" source="Time" foreignKey="time_id"/>
        <Dimension name="Alternative Promotion" foreignKey="promotion_id">
          <Hierarchy hasAll="true" primaryKey="promo_id">
            <InlineTable alias="alt_promotion">
              <ColumnDefs>
                <ColumnDef name="promo_id" type="Numeric"/>
                <ColumnDef name="promo_name" type="String"/>
              </ColumnDefs>
              <Rows>
                <Row>
                  <Value column="promo_id">0</Value>
                  <Value column="promo_name">Promo0</Value>
                </Row>
                <Row>
                  <Value column="promo_id">1</Value>
                </Row>
              </Rows>
            </InlineTable>
            <Level name="Alternative Promotion" column="promo_name" uniqueMembers="true"/>
          </Hierarchy>
        </Dimension>
        <Measure name="Unit Sales" column="unit_sales" aggregator="sum"
            formatString="Standard" visible="false"/>
        <Measure name="Store Sales" column="store_sales" aggregator="sum"
            formatString="#,###.00"/>
      </Cube>
    XML

    # This test should work irrespective of the case-sensitivity setting.
    olap = connection_with_new_cube(cube_xml)
    begin
      [true, false].each do |case_sensitive|
        with_properties(CaseSensitive: case_sensitive) do
          assert_query_returns olap,
            "SELECT {[Measures].[Unit Sales]} ON COLUMNS, " \
            "{[Alternative Promotion].[#null]} ON ROWS " \
            "FROM [Sales_inline]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Measures].[Unit Sales]}
              Axis #2:
              {[Alternative Promotion].[#null]}
              Row #0: \n
            RESULT
        end
      end
    ensure
      olap.close
    end
  end

  # Java: CompatibilityTest#testNullNameColumn
  it "data in Hierarchy.Level nameColumn attribute can be null" do
    skip "Non-default null member representation" unless default_null_member_representation?

    cube_xml = <<~XML
      <Cube name="Sales_inline">
        <Table name="sales_fact_1997"/>
        <DimensionUsage name="Time" source="Time" foreignKey="time_id"/>
        <Dimension name="Alternative Promotion" foreignKey="promotion_id">
          <Hierarchy hasAll="true" primaryKey="promo_id">
            <InlineTable alias="alt_promotion">
              <ColumnDefs>
                <ColumnDef name="promo_id" type="Numeric"/>
                <ColumnDef name="promo_name" type="String"/>
              </ColumnDefs>
              <Rows>
                <Row>
                  <Value column="promo_id">0</Value>
                </Row>
                <Row>
                  <Value column="promo_id">1</Value>
                  <Value column="promo_name">Promo1</Value>
                </Row>
              </Rows>
            </InlineTable>
            <Level name="Alternative Promotion" column="promo_id" nameColumn="promo_name" uniqueMembers="true"/>
          </Hierarchy>
        </Dimension>
        <Measure name="Unit Sales" column="unit_sales" aggregator="sum"
            formatString="Standard" visible="false"/>
        <Measure name="Store Sales" column="store_sales" aggregator="sum"
            formatString="#,###.00"/>
      </Cube>
    XML

    olap = connection_with_new_cube(cube_xml)
    begin
      assert_query_returns olap,
        "SELECT {[Alternative Promotion].[#null], [Alternative Promotion].[Promo1]} ON COLUMNS " \
        "FROM [Sales_inline]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Alternative Promotion].[#null]}
          {[Alternative Promotion].[Promo1]}
          Row #0: 195,448
          Row #0: \n
        RESULT
    ensure
      olap.close
    end
  end

  # Java: CompatibilityTest#testNullCollation
  it "NULL values sort last on all platforms" do
    dialect = @olap.raw_mondrian_connection.getSchema.getDialect
    skip "Dialect does not support GROUP BY expressions" unless dialect.supportsGroupByExpressions

    cube_xml = <<~XML
      <Cube name="Store_NullsCollation">
        <Table name="store"/>
        <Dimension name="Store" foreignKey="store_id">
          <Hierarchy hasAll="true" primaryKey="store_id">
            <Level name="Store Name" column="store_name" uniqueMembers="true">
             <OrdinalExpression>
              <SQL dialect="access">
                 Iif(store_name = 'HQ', null, store_name)
             </SQL>
              <SQL dialect="oracle">
                 case "store_name" when 'HQ' then null else "store_name" end
             </SQL>
              <SQL dialect="hsqldb">
                 case "store_name" when 'HQ' then null else "store_name" end
             </SQL>
              <SQL dialect="db2">
                 case "store"."store_name" when 'HQ' then null else "store"."store_name" end
             </SQL>
              <SQL dialect="luciddb">
                 case "store_name" when 'HQ' then null else "store_name" end
             </SQL>
              <SQL dialect="netezza">
                 case "store_name" when 'HQ' then null else "store_name" end
             </SQL>
              <SQL dialect="generic">
                 case store_name when 'HQ' then null else store_name end
             </SQL>
             </OrdinalExpression>
              <Property name="Store Sqft" column="store_sqft" type="Numeric"/>
            </Level>
          </Hierarchy>
        </Dimension>
        <Measure name="Store Sqft" column="store_sqft" aggregator="sum"
            formatString="#,###"/>
      </Cube>
    XML

    olap = connection_with_new_cube(cube_xml)
    begin
      assert_query_returns olap,
        "SELECT { [Measures].[Store Sqft] } ON COLUMNS, " \
        "NON EMPTY TopCount({[Store].[Store Name].Members}, 5, [Measures].[Store Sqft]) ON ROWS " \
        "FROM [Store_NullsCollation]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Store Sqft]}
          Axis #2:
          {[Store].[Store 3]}
          {[Store].[Store 18]}
          {[Store].[Store 9]}
          {[Store].[Store 10]}
          {[Store].[Store 20]}
          Row #0: 39,696
          Row #1: 38,382
          Row #2: 36,509
          Row #3: 34,791
          Row #4: 34,452
        RESULT
    ensure
      olap.close
    end
  end

  # Java: CompatibilityTest#testPropertyCaseSensitivity
  it "property names are case sensitive iff mondrian.olap.case.sensitive is set" do
    case_sensitive = Java::MondrianOlap::MondrianProperties.instance.CaseSensitive.get

    # A user-defined property of a member
    assert_expression_returns @olap,
      '[Store].[USA].[CA].[Beverly Hills].[Store 6].Properties("Store Type")',
      "Gourmet Supermarket"

    if case_sensitive
      assert_expression_raises @olap,
        '[Store].[USA].[CA].[Beverly Hills].[Store 6].Properties("store tYpe")',
        "Property 'store tYpe' is not valid for member '[Store].[USA].[CA].[Beverly Hills].[Store 6]'"
    else
      assert_expression_returns @olap,
        '[Store].[USA].[CA].[Beverly Hills].[Store 6].Properties("store tYpe")',
        "Gourmet Supermarket"
    end

    # A builtin property of a member
    assert_expression_returns @olap,
      '[Store].[USA].[CA].[Beverly Hills].[Store 6].Properties("LEVEL_NUMBER")',
      "4"

    if case_sensitive
      assert_expression_raises @olap,
        '[Store].[USA].[CA].[Beverly Hills].[Store 6].Properties("Level_Number")',
        "Property 'Level_Number' is not valid for member '[Store].[USA].[CA].[Beverly Hills].[Store 6]'"
    else
      assert_expression_returns @olap,
        '[Store].[USA].[CA].[Beverly Hills].[Store 6].Properties("Level_Number")',
        "4"
    end

    # Cell properties
    # Java uses mondrian.olap.Result.getCell(int[]).getPropertyValue(String).
    # We use the internal Mondrian API to match the Java test exactly.
    mondrian_connection = @olap.raw_mondrian_connection
    query = mondrian_connection.parseQuery(
      "SELECT {[Measures].[Unit Sales],[Measures].[Store Sales]} ON COLUMNS, " \
      "{[Gender].[M]} ON ROWS FROM Sales"
    )
    mondrian_result = mondrian_connection.execute(query)
    cell = mondrian_result.getCell([0, 0].to_java(:int))
    assert_equal "135,215", cell.getPropertyValue("FORMATTED_VALUE")

    if case_sensitive
      # When case sensitive, differently-cased key should return nil
      assert_nil cell.getPropertyValue("Formatted_Value")
    else
      assert_equal "135,215", cell.getPropertyValue("Formatted_Value")
    end
  end

  describe "dimension prefix" do
    # Java: CompatibilityTest#testWithDimensionPrefix
    it "works with and without dimension prefix requirement" do
      [true, false].each do |prefix_needed|
        with_properties(NeedDimensionPrefix: prefix_needed) do
          assert_axis_returns @olap, "[Gender].[M]", "[Gender].[M]"
          assert_axis_returns @olap, "[Gender].[All Gender].[M]", "[Gender].[M]"
          assert_axis_returns @olap, "[Store].[USA]", "[Store].[USA]"
          assert_axis_returns @olap, "[Store].[All Stores].[USA]", "[Store].[USA]"
        end
      end
    end

    # Java: CompatibilityTest#testWithNoDimensionPrefix
    it "resolves members without dimension prefix when not required" do
      with_properties(NeedDimensionPrefix: false) do
        assert_axis_returns @olap, "{[M]}", "[Gender].[M]"
        assert_axis_returns @olap, "{M}", "[Gender].[M]"
        assert_axis_returns @olap, "{[USA].[CA]}", "[Store].[USA].[CA]"
        assert_axis_returns @olap, "{USA.CA}", "[Store].[USA].[CA]"
      end

      with_properties(NeedDimensionPrefix: true) do
        assert_axis_throws @olap,
          "{[M]}",
          "Mondrian Error:MDX object '[M]' not found in cube 'Sales'"

        assert_axis_throws @olap,
          "{M}",
          "Mondrian Error:MDX object 'M' not found in cube 'Sales'"

        assert_axis_throws @olap,
          "{[USA].[CA]}",
          "Mondrian Error:MDX object '[USA].[CA]' not found in cube 'Sales'"

        assert_axis_throws @olap,
          "{USA.CA}",
          "Mondrian Error:MDX object 'USA.CA' not found in cube 'Sales'"
      end
    end
  end

  private

  # Assert that an expression wrapped in a calculated member returns a cell-level error
  # matching the pattern. Checks both thrown exceptions and cell error values.
  def assert_expression_raises(olap, expression, pattern)
    escaped = expression.gsub("'", "''")
    mdx = "WITH MEMBER [Measures].[Foo] AS '#{escaped}' " \
          "SELECT {[Measures].[Foo]} ON COLUMNS FROM [Sales]"
    begin
      result = olap.execute(mdx)
      cell_value = result.values.flatten.first.to_s
      assert cell_value.include?(pattern),
        "Expected error containing '#{pattern}', got cell value: #{cell_value}"
    rescue Mondrian::OLAP::Error => e
      cause = e
      cause = cause.cause while cause.cause && cause.cause != cause
      assert cause.message.include?(pattern),
        "Expected error containing '#{pattern}', got: #{cause.message}"
    end
  end
end
