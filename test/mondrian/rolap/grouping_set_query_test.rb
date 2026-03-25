# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2004-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/GroupingSetQueryTest.java
#
# Most tests in this class use the internal BatchTestCase.createRequest /
# assertRequestSql API to construct CellRequest objects, feed them to
# FastBatchingCellReader, and assert exact SQL via a TriggerHook / Bomb
# mechanism.  Replicating that pipeline in JRuby requires reflection into
# several package-private classes (FastBatchingCellReader, RolapStar internals,
# ValueColumnPredicate, etc.).
#
# The SQL-pattern tests below are currently skipped with FIXME.  Each test body
# contains the expected SQL patterns from the Java source and an MDX-based
# approximation using capture_sql — kept as a starting point for a faithful
# reproduction.
#
# To make these tests 1:1 with Java, you would need to:
#   1. Access RolapStar.Measure via the internal Mondrian connection:
#        cube = connection.getSchema.lookupCube(name, true)
#        member = cube.getSchemaReader(nil).getMemberByUniqueName(...)
#        star_measure = Java::MondrianRolap::RolapStar.getStarMeasure(member)
#   2. Construct CellRequest objects:
#        Java::MondrianRolapAgg::CellRequest.new(star_measure, false, false)
#   3. Add constrained columns via star.lookupColumn(table, column) and
#      ValueColumnPredicate.
#   4. Instantiate FastBatchingCellReader (package-private — use reflection),
#      call recordCellRequest for each request, then loadAggregations inside
#      a Locus context.
#   5. Use RolapUtil.setHook with a TriggerHook-like callback (SqlCapture's
#      SqlLogger is close) to intercept and assert on the exact SQL.
#   6. Clear the cube's aggregation cache before each assertion
#      (see BatchTestCase.clearCache).
describe "GroupingSetQuery" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # -- SQL pattern helpers (used by the skipped tests as a starting point) --

  # Replace =as= placeholder per dialect.
  # Oracle omits alias keyword; Teradata/PostgreSQL use "as".
  def dialectize_sql(sql)
    case MONDRIAN_DRIVER
    when "oracle"                 then sql.gsub(" =as= ", " ")
    when "teradata", "postgresql" then sql.gsub(" =as= ", " as ")
    else sql.gsub(" =as= ", " as ")
    end
  end

  def normalize_sql(sql)
    sql.gsub(/\s+/, " ").strip
  end

  # Execute MDX with a fresh connection (clean cache) and capture all generated SQL.
  def execute_and_capture_sql(mdx, **properties)
    all_properties = {GenerateFormattedSql: false}.merge(properties)
    with_properties(**all_properties) do
      Mondrian::OLAP::Connection.flush_schema_cache
      connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        captured = capture_sql { connection.execute(mdx) }
        captured.map { |s| normalize_sql(s) }
      ensure
        connection.close
        Mondrian::OLAP::Connection.flush_schema_cache
      end
    end
  end

  # Assert that expected SQL (with =as= placeholders) appears among captured queries.
  def assert_sql_found(captured, expected_raw)
    expected = normalize_sql(dialectize_sql(expected_raw))
    found = captured.any? { |q| q.include?(expected) }
    assert found, "Expected SQL not found.\nExpected:\n  #{expected}\nCaptured (#{captured.size}):\n  #{captured.join("\n  ")}"
  end

  def aggregates_enabled?
    properties = Java::MondrianOlap::MondrianProperties.instance
    properties.ReadAggregates.get && properties.UseAggregates.get
  end

  # -- Tests --

  # Java: GroupingSetQueryTest#testGroupingSetsWithAggregateOverDefaultMember
  it "grouping sets with aggregate over default member" do
    # Testcase for MONDRIAN-705.
    # The Java test conditionally enables grouping sets if the dialect supports it.
    with_properties(EnableGroupingSets: true) do
      assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
        with member [Gender].[agg] as
          'Aggregate({[Gender].DefaultMember}, [Measures].[Store Cost])'
        select
          {[Measures].[Store Cost]} ON COLUMNS,
          {[Gender].[Gender].Members, [Gender].[agg]} ON ROWS
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Store Cost]}
        Axis #2:
        {[Gender].[F]}
        {[Gender].[M]}
        {[Gender].[agg]}
        Row #0: 111,777.48
        Row #1: 113,849.75
        Row #2: 225,627.23
      RESULT
    end
  end

  # Java: GroupingSetQueryTest#testGroupingSetForSingleColumnConstraint
  #
  # Java creates 3 CellRequests on Sales 2 / Unit Sales:
  #   - customer.gender = "M", customer.gender = "F", and total (no constraint)
  # Then calls assertRequestSql with SQL patterns for Oracle/Teradata (with and
  # without GROUPING SETS) and Access (without).  When aggregates are enabled,
  # different patterns targeting agg tables are used instead.
  #
  # This test uses MDX + capture_sql which is a different code path from the
  # internal CellRequest / FastBatchingCellReader pipeline.  The SQL patterns
  # below are copied from the Java source for reference.
  it "grouping set for single column constraint" do
    skip "FIXME: Needs createRequest/assertRequestSql via reflection (see class comment)"

    mdx = "SELECT {[Measures].[Unit Sales]} ON 0, {[Gender].Members} ON 1 FROM [Sales 2]"

    if aggregates_enabled?
      captured = execute_and_capture_sql(mdx, DisableCaching: false, EnableGroupingSets: true)
      assert_sql_found captured,
        'select sum("agg_c_10_sales_fact_1997"."unit_sales") as "m0"' \
        ' from "agg_c_10_sales_fact_1997" =as= "agg_c_10_sales_fact_1997"'
      assert_sql_found captured,
        'select "agg_g_ms_pcat_sales_fact_1997"."gender" as "c0",' \
        ' sum("agg_g_ms_pcat_sales_fact_1997"."unit_sales") as "m0"' \
        ' from "agg_g_ms_pcat_sales_fact_1997" =as= "agg_g_ms_pcat_sales_fact_1997"' \
        ' group by "agg_g_ms_pcat_sales_fact_1997"."gender"'
    else
      captured = execute_and_capture_sql(mdx, DisableCaching: false, EnableGroupingSets: true)
      assert_sql_found captured,
        'select "customer"."gender" as "c0", sum("sales_fact_1997"."unit_sales") as "m0",' \
        ' grouping("customer"."gender") as "g0"' \
        ' from "customer" =as= "customer", "sales_fact_1997" =as= "sales_fact_1997"' \
        ' where "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
        ' group by grouping sets (("customer"."gender"), ())'

      captured = execute_and_capture_sql(mdx, DisableCaching: false, EnableGroupingSets: false)
      assert_sql_found captured,
        'select "customer"."gender" as "c0", sum("sales_fact_1997"."unit_sales") as "m0"' \
        ' from "customer" =as= "customer", "sales_fact_1997" =as= "sales_fact_1997"' \
        ' where "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
        ' group by "customer"."gender"'
    end
  end

  # Java: GroupingSetQueryTest#testNotUsingGroupingSetWhenGroupUsesDifferentAggregateTable
  #
  # Only runs when UseAggregates and ReadAggregates are both enabled (returns
  # early otherwise).  Creates 3 CellRequests on Sales / Unit Sales with Gender
  # constraint + total, then asserts SQL uses agg table (not grouping sets)
  # because the detail and summary resolve to different aggregate tables.
  it "not using grouping set when group uses different aggregate table" do
    skip "FIXME: Needs createRequest/assertRequestSql via reflection (see class comment)"

    # Java: if (!(prop.UseAggregates.get() && prop.ReadAggregates.get())) return;
    # This test is a no-op unless aggregates are enabled.

    mdx = "SELECT {[Measures].[Unit Sales]} ON 0, {[Gender].Members} ON 1 FROM [Sales]"
    captured = execute_and_capture_sql(mdx, EnableGroupingSets: true)
    assert_sql_found captured,
      'select "agg_g_ms_pcat_sales_fact_1997"."gender" as "c0",' \
      ' sum("agg_g_ms_pcat_sales_fact_1997"."unit_sales") as "m0"' \
      ' from "agg_g_ms_pcat_sales_fact_1997" =as= "agg_g_ms_pcat_sales_fact_1997"' \
      ' group by "agg_g_ms_pcat_sales_fact_1997"."gender"'
  end

  # Java: GroupingSetQueryTest#testNotUsingGroupingSet
  #
  # Creates 2 CellRequests on Sales 2 / Unit Sales: Gender M and Gender F
  # (no total).  Without a summary row there is nothing to merge via grouping
  # sets, so both EnableGroupingSets true/false produce regular GROUP BY.
  # Skipped when aggregates are enabled.
  it "not using grouping set" do
    skip "FIXME: Needs createRequest/assertRequestSql via reflection (see class comment)"

    mdx = "SELECT {[Measures].[Unit Sales]} ON 0, {[Gender].[Gender].Members} ON 1 FROM [Sales 2]"

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: true)
    assert_sql_found captured,
      'select "customer"."gender" as "c0", sum("sales_fact_1997"."unit_sales") as "m0"' \
      ' from "customer" =as= "customer", "sales_fact_1997" =as= "sales_fact_1997"' \
      ' where "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
      ' group by "customer"."gender"'

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: false)
    assert_sql_found captured,
      'select "customer"."gender" as "c0", sum("sales_fact_1997"."unit_sales") as "m0"' \
      ' from "customer" =as= "customer", "sales_fact_1997" =as= "sales_fact_1997"' \
      ' where "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
      ' group by "customer"."gender"'
  end

  # Java: GroupingSetQueryTest#testGroupingSetForMultipleMeasureAndSingleConstraint
  #
  # Creates 6 CellRequests on Sales 2: Unit Sales + Store Sales, each with
  # Gender M/F + total.  With grouping sets, both measures appear in one query
  # with a GROUPING SETS clause.  Skipped when aggregates are enabled.
  it "grouping set for multiple measure and single constraint" do
    skip "FIXME: Needs createRequest/assertRequestSql via reflection (see class comment)"

    mdx = "SELECT {[Measures].[Unit Sales], [Measures].[Store Sales]} ON 0, {[Gender].Members} ON 1 FROM [Sales 2]"

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: true)
    assert_sql_found captured,
      'select "customer"."gender" as "c0", sum("sales_fact_1997"."unit_sales") as "m0",' \
      ' sum("sales_fact_1997"."store_sales") as "m1", grouping("customer"."gender") as "g0"' \
      ' from "customer" =as= "customer", "sales_fact_1997" =as= "sales_fact_1997"' \
      ' where "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
      ' group by grouping sets (("customer"."gender"), ())'

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: false)
    assert_sql_found captured,
      'select "customer"."gender" as "c0", sum("sales_fact_1997"."unit_sales") as "m0",' \
      ' sum("sales_fact_1997"."store_sales") as "m1"' \
      ' from "customer" =as= "customer", "sales_fact_1997" =as= "sales_fact_1997"' \
      ' where "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
      ' group by "customer"."gender"'
  end

  # Java: GroupingSetQueryTest#testGroupingSetForASummaryCanBeGroupedWith2DetailBatch
  #
  # Creates 6 CellRequests on Sales 2 / Unit Sales: Gender M/F + total AND
  # Marital Status M/S + total (duplicate totals).  Java uses the internal
  # CellRequest API to access customer.marital_status directly — Sales 2 has
  # no Marital Status MDX dimension so this cannot be replicated via MDX alone.
  #
  # The Gender batch gets GROUPING SETS (detail + summary); the Marital Status
  # batch gets regular GROUP BY.  Without grouping sets, a separate total query
  # is emitted.  Skipped when aggregates are enabled.
  it "grouping set for a summary can be grouped with 2 detail batch" do
    skip "FIXME: Needs createRequest/assertRequestSql via reflection (see class comment). " \
         "Also: Sales 2 has no Marital Status MDX dimension — the Java test accesses " \
         "customer.marital_status via internal CellRequest API"

    # Gender batch — MDX approximation on Sales 2
    mdx = "SELECT {[Measures].[Unit Sales]} ON 0, {[Gender].[Gender].Members} ON 1 FROM [Sales 2]"
    # Marital Status batch — must use Sales cube (has Marital Status dimension)
    mdx2 = "SELECT {[Measures].[Unit Sales]} ON 0, {[Marital Status].[Marital Status].Members} ON 1 FROM [Sales]"

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: true)
    assert_sql_found captured,
      'select "customer"."gender" as "c0", sum("sales_fact_1997"."unit_sales") as "m0",' \
      ' grouping("customer"."gender") as "g0"' \
      ' from "customer" =as= "customer", "sales_fact_1997" =as= "sales_fact_1997"' \
      ' where "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
      ' group by grouping sets (("customer"."gender"), ())'

    captured2 = execute_and_capture_sql(mdx2, EnableGroupingSets: true)
    assert_sql_found captured2,
      'select "customer"."marital_status" as "c0", sum("sales_fact_1997"."unit_sales") as "m0"' \
      ' from "customer" =as= "customer", "sales_fact_1997" =as= "sales_fact_1997"' \
      ' where "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
      ' group by "customer"."marital_status"'

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: false)
    assert_sql_found captured,
      'select sum("sales_fact_1997"."unit_sales") as "m0"' \
      ' from "sales_fact_1997" =as= "sales_fact_1997"'
  end

  # Java: GroupingSetQueryTest#testGroupingSetForMultipleColumnConstraint
  #
  # Creates 3 CellRequests on Sales 2 / Unit Sales with two-column constraints:
  #   - (Gender M, Year 1997), (Gender F, Year 1997), and (Year 1997) only.
  # With grouping sets, Gender is the grouping column while Year is shared.
  # Skipped when aggregates are enabled.
  it "grouping set for multiple column constraint" do
    skip "FIXME: Needs createRequest/assertRequestSql via reflection (see class comment)"

    mdx = <<~MDX
      SELECT {[Measures].[Unit Sales]} ON 0,
        CrossJoin({[Time].[1997]}, {[Gender].[Gender].Members}) ON 1
      FROM [Sales 2]
    MDX

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: true)
    assert_sql_found captured,
      'select "time_by_day"."the_year" as "c0", "customer"."gender" as "c1",' \
      ' sum("sales_fact_1997"."unit_sales") as "m0", grouping("customer"."gender") as "g0"' \
      ' from "time_by_day" =as= "time_by_day", "sales_fact_1997" =as= "sales_fact_1997", "customer" =as= "customer"' \
      ' where "sales_fact_1997"."time_id" = "time_by_day"."time_id" and "time_by_day"."the_year" = 1997' \
      ' and "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
      ' group by grouping sets (("time_by_day"."the_year", "customer"."gender"), ("time_by_day"."the_year"))'

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: false)
    assert_sql_found captured,
      'select "time_by_day"."the_year" as "c0", "customer"."gender" as "c1",' \
      ' sum("sales_fact_1997"."unit_sales") as "m0"' \
      ' from "time_by_day" =as= "time_by_day", "sales_fact_1997" =as= "sales_fact_1997",' \
      ' "customer" =as= "customer"' \
      ' where "sales_fact_1997"."time_id" = "time_by_day"."time_id" and' \
      ' "time_by_day"."the_year" = 1997' \
      ' and "sales_fact_1997"."customer_id" = "customer"."customer_id"' \
      ' group by "time_by_day"."the_year", "customer"."gender"'
  end

  # Java: GroupingSetQueryTest#testGroupingSetForMultipleColumnConstraintAndCompoundConstraint
  #
  # Creates 3 CellRequests on Sales 2 / Customer Count with two-column
  # constraints (Gender + Year) plus a compound constraint on store country/state
  # (USA/OR and CANADA/BC).  As of change 12310, grouping sets are removed from
  # distinct count queries, so both EnableGroupingSets modes produce the same SQL.
  #
  # Sales 2 has no Store dimension for MDX.  The Java test accesses
  # store.store_country / store.store_state via makeConstraintCountryState and
  # the internal CellRequest API.  The MDX approximation below uses the Sales
  # cube which has a Store hierarchy.
  it "grouping set for multiple column constraint and compound constraint" do
    skip "FIXME: Needs createRequest/assertRequestSql via reflection (see class comment). " \
         "Also: Sales 2 has no Store MDX dimension — the Java test accesses store columns " \
         "via makeConstraintCountryState / CellRequest API"

    mdx = <<~MDX
      SELECT {[Measures].[Customer Count]} ON 0,
        CrossJoin(
          CrossJoin({[Time].[1997]}, {[Gender].[Gender].Members}),
          {[Store].[USA].[OR], [Store].[Canada].[BC]}
        ) ON 1
      FROM [Sales]
    MDX

    expected_sql =
      'select "time_by_day"."the_year" as "c0", "customer"."gender" as "c1",' \
      ' count(distinct "sales_fact_1997"."customer_id") as "m0" from "time_by_day" =as= "time_by_day",' \
      ' "sales_fact_1997" =as= "sales_fact_1997", "customer" =as= "customer", "store" =as= "store"' \
      ' where "sales_fact_1997"."time_id" = "time_by_day"."time_id" and "time_by_day"."the_year" = 1997' \
      ' and "sales_fact_1997"."customer_id" = "customer"."customer_id" and' \
      ' "sales_fact_1997"."store_id" = "store"."store_id" and' \
      " ((\"store\".\"store_country\" = 'USA' and \"store\".\"store_state\" = 'OR') or" \
      " (\"store\".\"store_country\" = 'CANADA' and \"store\".\"store_state\" = 'BC'))" \
      ' group by "time_by_day"."the_year", "customer"."gender"'

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: true)
    assert_sql_found captured, expected_sql

    captured = execute_and_capture_sql(mdx, EnableGroupingSets: false)
    assert_sql_found captured, expected_sql
  end

  # Java: GroupingSetQueryTest#testBug2004202
  it "except working with grouping sets (bug 2004202)" do
    assert_query_returns @olap, <<~MDX.chomp, <<~RESULT
      with member store.allbutwallawalla as
       'aggregate(
          except(
              store.[store name].members,
              { [Store].[All Stores].[USA].[WA].[Walla Walla].[Store 22]}))'
      select {
                store.[store name].members,
               store.allbutwallawalla,
               store.[all stores]} on 0,
        {measures.[customer count]} on 1
      from sales
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Store].[Canada].[BC].[Vancouver].[Store 19]}
      {[Store].[Canada].[BC].[Victoria].[Store 20]}
      {[Store].[Mexico].[DF].[Mexico City].[Store 9]}
      {[Store].[Mexico].[DF].[San Andres].[Store 21]}
      {[Store].[Mexico].[Guerrero].[Acapulco].[Store 1]}
      {[Store].[Mexico].[Jalisco].[Guadalajara].[Store 5]}
      {[Store].[Mexico].[Veracruz].[Orizaba].[Store 10]}
      {[Store].[Mexico].[Yucatan].[Merida].[Store 8]}
      {[Store].[Mexico].[Zacatecas].[Camacho].[Store 4]}
      {[Store].[Mexico].[Zacatecas].[Hidalgo].[Store 12]}
      {[Store].[Mexico].[Zacatecas].[Hidalgo].[Store 18]}
      {[Store].[USA].[CA].[Alameda].[HQ]}
      {[Store].[USA].[CA].[Beverly Hills].[Store 6]}
      {[Store].[USA].[CA].[Los Angeles].[Store 7]}
      {[Store].[USA].[CA].[San Diego].[Store 24]}
      {[Store].[USA].[CA].[San Francisco].[Store 14]}
      {[Store].[USA].[OR].[Portland].[Store 11]}
      {[Store].[USA].[OR].[Salem].[Store 13]}
      {[Store].[USA].[WA].[Bellingham].[Store 2]}
      {[Store].[USA].[WA].[Bremerton].[Store 3]}
      {[Store].[USA].[WA].[Seattle].[Store 15]}
      {[Store].[USA].[WA].[Spokane].[Store 16]}
      {[Store].[USA].[WA].[Tacoma].[Store 17]}
      {[Store].[USA].[WA].[Walla Walla].[Store 22]}
      {[Store].[USA].[WA].[Yakima].[Store 23]}
      {[Store].[allbutwallawalla]}
      {[Store].[All Stores]}
      Axis #2:
      {[Measures].[Customer Count]}
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
      Row #0: 1,059
      Row #0: 1,147
      Row #0: 962
      Row #0: 296
      Row #0: 563
      Row #0: 474
      Row #0: 190
      Row #0: 179
      Row #0: 906
      Row #0: 84
      Row #0: 278
      Row #0: 96
      Row #0: 95
      Row #0: 5,485
      Row #0: 5,581
    RESULT
  end
end
