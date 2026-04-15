# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/NativeFilterAgainstAggTableTest.java
describe "NativeFilterAgainstAggTableTest" do
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

  # http://jira.pentaho.com/browse/MONDRIAN-2155
  # Aggregation table can have fact's count value exceeding 1,
  # so that to compute the overall amount of facts it is necessary
  # to sum the values instead of counting them.
  # Java: NativeFilterAgainstAggTableTest#testFilteringOnAggregated_ByCount
  it "filtering on aggregated by COUNT" do
    with_properties(
      UseAggregates: true,
      ReadAggregates: true,
      EnableNativeFilter: true,
      EnableNativeCrossJoin: true,
      EnableNativeNonEmpty: true
    ) do
      mdx = <<~MDX
        SELECT
          {FILTER(
            {[Product].[All Products].Children},
            [Measures].[Sales Count] < 15535
          )} ON COLUMNS,
          {[Measures].[Sales Count]} on ROWS
        FROM [Sales]
        WHERE [Time].[1997].[Q1]
      MDX

      assert_query_returns @olap, mdx, <<~RESULT
        Axis #0:
        {[Time].[1997].[Q1]}
        Axis #1:
        {[Product].[Drink]}
        {[Product].[Non-Consumable]}
        Axis #2:
        {[Measures].[Sales Count]}
        Row #0: 1,959
        Row #0: 4,090
      RESULT

      verify_same_native_and_not(mdx)
    end
  end

  # Java: NativeFilterAgainstAggTableTest#testFilteringOnAggregated_BySum
  it "filtering on aggregated by SUM" do
    with_properties(
      UseAggregates: true,
      ReadAggregates: true,
      EnableNativeFilter: true,
      EnableNativeCrossJoin: true,
      EnableNativeNonEmpty: true
    ) do
      mdx = <<~MDX
        SELECT
          {FILTER(
            {[Product].[All Products].Children},
            [Measures].[Store Sales] > 11586
          )} ON COLUMNS,
          {[Measures].[Store Sales]} on ROWS
        FROM [Sales]
        WHERE [Time].[1997].[Q1]
      MDX

      assert_query_returns @olap, mdx, <<~RESULT
        Axis #0:
        {[Time].[1997].[Q1]}
        Axis #1:
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        Axis #2:
        {[Measures].[Store Sales]}
        Row #0: 101,261.32
        Row #0: 26,781.23
      RESULT

      verify_same_native_and_not(mdx)
    end
  end

  # http://jira.pentaho.com/browse/MONDRIAN-1703
  # If a filter condition contains one or more measures that are
  # not present in the aggregate table, the SQL should omit the
  # having clause altogether.
  # Java: NativeFilterAgainstAggTableTest#testAggTableWithNotAllMeasures
  it "agg table with not all measures" do
    skip "MySQL-specific SQL pattern test" unless MONDRIAN_DRIVER == "mysql"

    with_properties(
      UseAggregates: true,
      ReadAggregates: true,
      EnableNativeFilter: true,
      EnableNativeCrossJoin: true,
      EnableNativeNonEmpty: true,
      GenerateFormattedSql: true
    ) do
      # This query should hit the agg_c_10_sales_fact_1997 agg table,
      # which has [unit sales] but not [store count], so should
      # not include the filter condition in the having.
      mdx_no_having = <<~MDX
        select filter(Time.[1997].children,
          measures.[Sales Count] + measures.[unit sales] > 0) on 0
        from [sales]
      MDX

      Mondrian::OLAP::Connection.flush_schema_cache
      connection = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        queries_no_having = capture_sql { connection.execute(mdx_no_having) }
        agg_table_queries = queries_no_having.select { |q| q.include?("agg_c_10_sales_fact_1997") }
        refute_empty agg_table_queries, "Expected SQL against agg_c_10_sales_fact_1997"

        # Verify no HAVING clause when not all measures are present
        agg_table_queries.each do |query|
          refute query.downcase.include?("having"),
            "SQL should not contain HAVING clause when not all measures are in the agg table.\nSQL: #{query}"
        end

        # Both measures are present on the agg table, so this one *should*
        # include having.
        mdx_with_having = <<~MDX
          select filter(Time.[1997].children,
            measures.[Store Sales] + measures.[unit sales] > 0) on 0
          from [sales]
        MDX

        queries_with_having = capture_sql { connection.execute(mdx_with_having) }
        agg_table_queries_having = queries_with_having.select { |q| q.include?("agg_c_10_sales_fact_1997") }
        refute_empty agg_table_queries_having, "Expected SQL against agg_c_10_sales_fact_1997"

        # Verify HAVING clause is present with the specific expression when both measures exist in agg table
        having_query = agg_table_queries_having.detect { |q| q.downcase.include?("having") }
        assert having_query,
          "SQL should contain HAVING clause when both measures are in the agg table.\nCaptured:\n#{agg_table_queries_having.join("\n---\n")}"

        # Verify the HAVING expression content matches the expected pattern
        assert_match(
          /sum\(`agg_c_10_sales_fact_1997`\.`store_sales`\)\s*\+\s*sum\(`agg_c_10_sales_fact_1997`\.`unit_sales`\)\)\s*>\s*0/,
          having_query,
          "HAVING clause should contain the full expression: sum(`agg_c_10_sales_fact_1997`.`store_sales`) + sum(`agg_c_10_sales_fact_1997`.`unit_sales`) > 0\nSQL: #{having_query}"
        )
      ensure
        connection&.close
      end
    end
  end
end
