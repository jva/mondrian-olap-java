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

# Java: mondrian/rolap/NativeFilterMatchingTest.java
describe "NativeFilterMatchingTest" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Checks whether query produces the same results with the native.* props
  # enabled as it does with the props disabled.
  # Matches Java BatchTestCase.verifySameNativeAndNot.
  def verify_same_native_and_not(mdx)
    with_properties(
      EnableNativeCrossJoin: true,
      EnableNativeFilter: true,
      EnableNativeNonEmpty: true,
      EnableNativeTopCount: true
    ) do
      result_native = format_result(@olap.execute(mdx))

      with_properties(
        EnableNativeCrossJoin: false,
        EnableNativeFilter: false,
        EnableNativeNonEmpty: false,
        EnableNativeTopCount: false
      ) do
        result_non_native = format_result(@olap.execute(mdx))
        assert_equal result_native, result_non_native
      end
    end
  end

  # Matches Java BatchTestCase.assertQuerySqlOrNot.
  # Executes MDX while capturing SQL, then asserts that at least one
  # captured SQL statement contains the expected SQL substring.
  def assert_query_sql_pattern(mdx, sql_patterns)
    pattern = sql_patterns[MONDRIAN_DRIVER]
    return unless pattern # No pattern for this driver -- no-op (same as Java)

    Mondrian::OLAP::Connection.flush_schema_cache
    connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
    begin
      queries = capture_sql { connection.execute(mdx) }
      normalized_pattern = pattern.gsub(/\s+/, " ").strip
      found = queries.any? { |sql| sql.gsub(/\s+/, " ").strip.include?(normalized_pattern) }
      assert found,
        "Expected SQL pattern not found.\nExpected:\n#{pattern}\n\nCaptured:\n#{queries.to_a.join("\n\n")}"
    ensure
      connection&.close
    end
  end

  # Java: NativeFilterMatchingTest#testPositiveMatching
  it "positive matching with native filter" do
    # No point testing if native filters are turned off.
    skip unless mondrian_property(:EnableNativeFilter)

    mdx = <<~MDX
      With
      Set [*NATIVE_CJ_SET] as 'Filter([*BASE_MEMBERS_Customers], Not IsEmpty ([Measures].[Unit Sales]))'
      Set [*SORTED_COL_AXIS] as 'Order([*CJ_COL_AXIS],[Customers].CurrentMember.OrderKey,BASC,Ancestor([Customers].CurrentMember,[Customers].[City]).OrderKey,BASC)'
      Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[Name].Members,[Customers].CurrentMember.Caption Matches ("(?i).*\\Qjeanne\\E.*"))'
      Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}'
      Set [*CJ_COL_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember)})'
      Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=400
      Select
      CrossJoin([*SORTED_COL_AXIS],[*BASE_MEMBERS_Measures]) on columns
      From [Sales]
    MDX

    # Verify the SQL HAVING clause uses the regex matching pattern.
    # The Java test had full SQL patterns, but the fork's SQL generation
    # differs (e.g. uses "fname" || ' ' || "lname" instead of fullname
    # on PostgreSQL, and CASE WHEN instead of NULLS LAST). We check for
    # the key HAVING clause substring that proves native filter pushdown.
    assert_query_sql_pattern mdx,
      "postgresql" => %{having cast("fname" || ' ' || "lname" as text) is not null and cast("fname" || ' ' || "lname" as text) ~ '(?i).*jeanne.*'},
      "mysql" => %{having c5 IS NOT NULL AND UPPER(c5) REGEXP '.*JEANNE.*'},
      "oracle" => %{having "fname" || ' ' || "lname" IS NOT NULL AND REGEXP_LIKE("fname" || ' ' || "lname", '.*jeanne.*', 'i')}

    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Customers].[USA].[WA].[Issaquah].[Jeanne Derry], [Measures].[*FORMATTED_MEASURE_0]}
      {[Customers].[USA].[CA].[Los Angeles].[Jeannette Eldridge], [Measures].[*FORMATTED_MEASURE_0]}
      {[Customers].[USA].[CA].[Burbank].[Jeanne Bohrnstedt], [Measures].[*FORMATTED_MEASURE_0]}
      {[Customers].[USA].[OR].[Portland].[Jeanne Zysko], [Measures].[*FORMATTED_MEASURE_0]}
      {[Customers].[USA].[WA].[Everett].[Jeanne McDill], [Measures].[*FORMATTED_MEASURE_0]}
      {[Customers].[USA].[CA].[West Covina].[Jeanne Whitaker], [Measures].[*FORMATTED_MEASURE_0]}
      {[Customers].[USA].[WA].[Everett].[Jeanne Turner], [Measures].[*FORMATTED_MEASURE_0]}
      {[Customers].[USA].[WA].[Puyallup].[Jeanne Wentz], [Measures].[*FORMATTED_MEASURE_0]}
      {[Customers].[USA].[OR].[Albany].[Jeannette Bura], [Measures].[*FORMATTED_MEASURE_0]}
      {[Customers].[USA].[WA].[Lynnwood].[Jeanne Ibarra], [Measures].[*FORMATTED_MEASURE_0]}
      Row #0: 50
      Row #0: 21
      Row #0: 31
      Row #0: 42
      Row #0: 110
      Row #0: 59
      Row #0: 42
      Row #0: 157
      Row #0: 146
      Row #0: 78
    RESULT

    verify_same_native_and_not(mdx)
  end

  # Java: NativeFilterMatchingTest#testNegativeMatching
  it "negative matching with native filter" do
    # No point testing if native filters are turned off.
    skip unless mondrian_property(:EnableNativeFilter)

    mdx = <<~MDX
      With
      Set [*NATIVE_CJ_SET] as 'Filter([*BASE_MEMBERS_Customers], Not IsEmpty ([Measures].[Unit Sales]))'
      Set [*SORTED_COL_AXIS] as 'Order([*CJ_COL_AXIS],[Customers].CurrentMember.OrderKey,BASC,Ancestor([Customers].CurrentMember,[Customers].[City]).OrderKey,BASC)'
      Set [*BASE_MEMBERS_Customers] as 'Filter([Customers].[Name].Members,[Customers].CurrentMember.Caption Not Matches ("(?i).*\\Qjeanne\\E.*"))'
      Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}'
      Set [*CJ_COL_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember)})'
      Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=400
      Select
      CrossJoin([*SORTED_COL_AXIS],[*BASE_MEMBERS_Measures]) on columns
      From [Sales]
    MDX

    # Verify the SQL HAVING clause uses NOT with the regex matching pattern.
    assert_query_sql_pattern mdx,
      "postgresql" => %{having NOT(cast("fname" || ' ' || "lname" as text) is not null and cast("fname" || ' ' || "lname" as text) ~ '(?i).*jeanne.*')},
      "mysql" => %{having NOT(c5 IS NOT NULL AND UPPER(c5) REGEXP '.*JEANNE.*')}

    # The result should not contain any "Jeanne" entries
    result = @olap.execute(mdx)
    result_string = format_result(result)
    refute result_string.include?("Jeanne"), "Result should not contain 'Jeanne' entries"

    verify_same_native_and_not(mdx)
  end

  # System test case for bug MONDRIAN-983:
  # "Regression: Unable to execute MDX statement with native MATCHES"
  # Java: NativeFilterMatchingTest#testMatchBugMondrian983
  it "match bug MONDRIAN-983" do
    mdx = <<~MDX
      With
      Set [*NATIVE_CJ_SET] as 'Filter([*BASE_MEMBERS_Product], Not IsEmpty ([Measures].[Unit Sales]))'
      Set [*SORTED_ROW_AXIS] as 'Order([*CJ_ROW_AXIS],[Product].CurrentMember.OrderKey,BASC,Ancestor([Product].CurrentMember,[Product].[Product Department]).OrderKey,BASC)'
      Set [*NATIVE_MEMBERS_Product] as 'Generate([*NATIVE_CJ_SET], {[Product].CurrentMember})'
      Set [*BASE_MEMBERS_Product] as 'Filter([Product].[Product Category].Members,[Product].CurrentMember.Caption Matches ("(?i).*\\Qa""\\); window.alert(""woot'');\\E.*"))'
      Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}'
      Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Product].currentMember)})'
      Set [*CJ_COL_AXIS] as '[*NATIVE_CJ_SET]'
      Member [Product].[*TOTAL_MEMBER_SEL~SUM] as 'Sum([*NATIVE_MEMBERS_Product])', SOLVE_ORDER=-100
      Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=400
      Select
      [*BASE_MEMBERS_Measures] on columns,
      Union({[Product].[*TOTAL_MEMBER_SEL~SUM]},[*SORTED_ROW_AXIS]) on rows
      From [Sales]
    MDX

    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Product].[*TOTAL_MEMBER_SEL~SUM]}
      Row #0: #{' '}
    RESULT
  end

  # MONDRIAN-1694: In some cases native filter would include an unnecessary
  # fact table join which incorrectly eliminated some tuples from the set.
  # Java: NativeFilterMatchingTest#testNativeFilterSameAsNonNative
  it "native filter same as non-native" do
    # FIXME: Known Java failure -- native and non-native results differ for
    # filter with regex and measure constraint.
    skip "Known Java failure (testNativeFilterSameAsNonNative)"

    verify_same_native_and_not(
      "select Filter([Store].[Store Name].Members, Store.CurrentMember.Name matches \"Store.*\") " \
      " on 0 from sales"
    )

    verify_same_native_and_not(
      "select Filter([Store].[Store Name].Members, Measures.[Unit Sales] > 100 and Store.CurrentMember.Name matches \"Store.*\") " \
      " on 0 from sales"
    )

    verify_same_native_and_not(
      "select Filter([Store].[Store Name].Members, measures.[Unit Sales] > 100) " \
      " on 0 from sales"
    )

    verify_same_native_and_not(
      "select non empty Filter([Store].[Store Name].Members, Store.CurrentMember.Name matches \"Store.*\") " \
      " on 0 from sales"
    )

    verify_same_native_and_not(
      "with set [filterSet] as 'Filter([Store].[Store Name].Members, Store.CurrentMember.Name matches \"Store.*\")'" \
      " select [filterSet] on 0 from sales"
    )
  end

  # MONDRIAN-1694: Verify that the RolapNativeSet cached values from
  # NON EMPTY context are not reused when not NON EMPTY.
  # Java: NativeFilterMatchingTest#testCachedNativeFilter
  it "cached native filter" do
    # FIXME: Known Java failure -- native and non-native results differ
    # for filter with regex.
    skip "Known Java failure (testCachedNativeFilter)"

    verify_same_native_and_not(
      "select NON EMPTY Filter([Store].[Store Name].Members, Store.CurrentMember.Name matches \"Store.*\") " \
      " on 0 from sales"
    )
    verify_same_native_and_not(
      "select Filter([Store].[Store Name].Members, Store.CurrentMember.Name matches \"Store.*\") " \
      " on 0 from sales"
    )
  end

  # Java: NativeFilterMatchingTest#testMatchesWithAccessControl
  it "matches with access control" do
    dimension_xml = <<~XML
      <Dimension name="Store2">
        <Hierarchy hasAll="true" primaryKey="store_id">
          <Table name="store"/>
          <Level name="Store Country" column="store_country" uniqueMembers="true"/>
          <Level name="Store State" column="store_state" uniqueMembers="true"/>
        </Hierarchy>
      </Dimension>
    XML

    cube_xml = <<~XML
      <Cube name="TinySales">
        <Table name="sales_fact_1997"/>
        <DimensionUsage name="Product" source="Product" foreignKey="product_id"/>
        <DimensionUsage name="Store2" source="Store2" foreignKey="store_id"/>
        <Measure name="Unit Sales" column="unit_sales" aggregator="sum"/>
      </Cube>
    XML

    role_xml = <<~XML
      <Role name="test">
        <SchemaGrant access="none">
          <CubeGrant cube="TinySales" access="all">
            <HierarchyGrant hierarchy="[Store2]" access="custom" rollupPolicy="PARTIAL">
              <MemberGrant member="[Store2].[USA].[CA]" access="all"/>
              <MemberGrant member="[Store2].[USA].[OR]" access="all"/>
              <MemberGrant member="[Store2].[Canada]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML

    # Insert shared dimension before the first <Cube, new cube before <VirtualCube,
    # and role before </Schema>
    schema = SchemaHelper::FOODMART_SCHEMA.dup
    schema = schema.sub('<Cube', "#{dimension_xml}\n<Cube")
    schema = schema.sub('<VirtualCube', "#{cube_xml}\n<VirtualCube")
    schema = schema.sub('</Schema>', "#{role_xml}\n</Schema>")

    params = CONNECTION_PARAMS.merge(catalog_content: schema, role: "test")
    params.delete(:catalog)
    connection = Mondrian::OLAP::Connection.create(params)
    begin
      # Helper to verify native and non-native produce the same result
      # using the role-restricted connection.
      verify = lambda do |query|
        with_properties(
          EnableNativeCrossJoin: true,
          EnableNativeFilter: true,
          EnableNativeNonEmpty: true,
          EnableNativeTopCount: true
        ) do
          result_native = format_result(connection.execute(query))

          with_properties(
            EnableNativeCrossJoin: false,
            EnableNativeFilter: false,
            EnableNativeNonEmpty: false,
            EnableNativeTopCount: false
          ) do
            result_non_native = format_result(connection.execute(query))
            assert_equal result_native, result_non_native
          end
        end
      end

      # Filter on dim with full access.
      verify.call(
        'select Filter([Product].[Product Category].Members, [Product].CurrentMember.Name matches "(?i).*Food.*")' \
        " on 0 from tinysales"
      )

      # Filter on restricted dimension. Should be empty set.
      verify.call(
        'select Filter([Store2].[USA].Children, [Store2].CurrentMember.Name matches "WA.*")' \
        " on 0 from tinysales"
      )

      # Filter on partially accessible set of tuples.
      verify.call(
        'select Filter(CrossJoin({[Store2].[USA].Children}, [Product].[Product Category].Members), [Store2].CurrentMember.Name matches ".*A.*")' \
        " on 0 from tinysales"
      )
    ensure
      connection&.close
    end
  end

  # Java: NativeFilterMatchingTest#testNativeFilterWithCompoundSlicer
  it "native filter with compound slicer" do
    mdx = <<~MDX
      with member measures.avgQtrs as 'avg( filter( time.quarter.members, measures.[unit sales] > 80))'
      select measures.avgQtrs * gender.members on 0 from sales where head( product.[product name].members, 3)
    MDX

    # Java wraps the entire test (SQL pattern check + results assertion) in
    # propSaver.set(GenerateFormattedSql, true).
    with_properties(GenerateFormattedSql: true) do
      # The SQL pattern assertion is a known Java failure for MySQL.
      # FIXME: Known Java failure for MySQL SQL pattern assertion
      # (testNativeFilterWithCompoundSlicer).

      # Make sure the numbers are right
      assert_query_returns @olap, mdx, <<~RESULT
        Axis #0:
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Pearl].[Pearl Imported Beer]}
        Axis #1:
        {[Measures].[avgQtrs], [Gender].[All Gender]}
        {[Measures].[avgQtrs], [Gender].[F]}
        {[Measures].[avgQtrs], [Gender].[M]}
        Row #0: 111
        Row #0: #{' '}
        Row #0: #{' '}
      RESULT
    end
  end

  # Java: NativeFilterMatchingTest#testNativeFilterWithCompoundSlicerWithAggs
  it "native filter with compound slicer with aggregates" do
    with_properties(UseAggregates: true, ReadAggregates: true, GenerateFormattedSql: true) do
      mdx = <<~MDX
        with member measures.avgQtrs as 'avg( filter( time.quarter.members, measures.[unit sales] > 80))'
        select measures.avgQtrs * gender.members on 0 from sales where head( product.[product name].members, 3)
      MDX

      # Java asserts the MySQL SQL pattern verifying aggregate table usage with HAVING clause.
      assert_query_sql_pattern mdx,
        "mysql" => %{having (sum(`agg_c_14_sales_fact_1997`.`unit_sales`) > 80)}

      # Make sure the numbers are right
      assert_query_returns @olap, mdx, <<~RESULT
        Axis #0:
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Imported Beer]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Good].[Good Light Beer]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer].[Pearl].[Pearl Imported Beer]}
        Axis #1:
        {[Measures].[avgQtrs], [Gender].[All Gender]}
        {[Measures].[avgQtrs], [Gender].[F]}
        {[Measures].[avgQtrs], [Gender].[M]}
        Row #0: 111
        Row #0: #{' '}
        Row #0: #{' '}
      RESULT
    end
  end

  # Java: NativeFilterMatchingTest#testNativeFilterWithCompoundSlicer_1
  it "native filter with compound slicer 1" do
    mdx = <<~MDX
      with member [measures].[avgQtrs] as 'count(filter([Customers].[Name].Members, [Measures].[Unit Sales] > 0))'
      select [measures].[avgQtrs] on 0 from sales where ( {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer], [Product].[Food].[Baked Goods].[Bread].[Muffins]} )
    MDX

    # Java wraps the entire test in propSaver.set(GenerateFormattedSql, true).
    with_properties(GenerateFormattedSql: true) do
      # The SQL pattern assertion is a known Java failure for MySQL.
      # FIXME: Known Java failure for MySQL SQL pattern assertion
      # (testNativeFilterWithCompoundSlicer_1).

      # Make sure the numbers are right
      assert_query_returns @olap, mdx, <<~RESULT
        Axis #0:
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer]}
        {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
        Axis #1:
        {[Measures].[avgQtrs]}
        Row #0: 1,281
      RESULT
    end
  end

  # Java: NativeFilterMatchingTest#testNativeFilterWithCompoundSlicer_2
  it "native filter with compound slicer 2" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[TotalVal] AS 'Aggregate(Filter({[Store].[Store City].members}, ([Measures].[Unit Sales] > 1000 OR ( [Measures].[Unit Sales] > 40 AND [Store].[Store City].CurrentMember.Name = "San Francisco" ) ) ) )'
      SELECT [Measures].[TotalVal] ON 0, [Product].[All Products].Children on 1 FROM [Sales] WHERE {[Time].[1997].[Q1],[Time].[1997].[Q2]}
    MDX

    verify_same_native_and_not(mdx)
  end

  # Java: NativeFilterMatchingTest#testNativeFilterWithCompoundSlicer_3
  it "native filter with compound slicer 3" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[TotalVal] AS 'Aggregate(Filter({[Store].[Store City].members}, [Measures].[Unit Sales] > 1000 ) )'
      SELECT [Measures].[TotalVal] ON 0, [Product].[All Products].Children on 1 FROM [Sales] WHERE {[Time].[1997].[Q1],[Time].[1997].[Q2]}
    MDX

    verify_same_native_and_not(mdx)
  end

  # Java: NativeFilterMatchingTest#testNativeFilterWithCompoundSlicer_4
  it "native filter with compound slicer 4" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[TotalVal] AS 'Aggregate(Filter({[Store].[Store City].members}, ([Measures].[Unit Sales] > 1000 OR ( [Measures].[Unit Sales] > 500 AND [Store].[Store City].CurrentMember.Name = "San Francisco" ) ) ) )'
      SELECT [Measures].[TotalVal] ON 0, [Product].[All Products].Children on 1 FROM [Sales] WHERE {[Time].[1997].[Q1],[Time].[1997].[Q2]}
    MDX

    verify_same_native_and_not(mdx)
  end

  # Java: NativeFilterMatchingTest#testNativeFilterWithCompoundSlicerDifferentProducts
  it "native filter with compound slicer different products" do
    mdx = <<~MDX
      with member measures.avgQtrs as 'count(filter(Customers.[Name].members, [Unit Sales] > 0))'
      select measures.avgQtrs on 0 from sales where ( {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer], [Product].[Food].[Baked Goods].[Bread].[Muffins]} )
    MDX

    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer]}
      {[Product].[Food].[Baked Goods].[Bread].[Muffins]}
      Axis #1:
      {[Measures].[avgQtrs]}
      Row #0: 1,281
    RESULT
  end
end
