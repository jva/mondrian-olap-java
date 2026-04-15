# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/rolap/aggmatcher/AggregationOverAggTableTest.java
describe "AggregationOverAggTable" do
  AGG_TABLE_NAME = "agg_c_avg_sales_fact_1997"

  # CSV data from aggregation-over-agg-table.csv
  # Columns: the_year, quarter, month_of_year, gender, unit_sales, fact_count
  AGG_TABLE_DATA = [
    [1997, "Q1", 1, "F", 677_784, 218_736],
    [1997, "Q1", 1, "M", 663_152, 217_372],
    [1997, "Q1", 2, "F", 574_896, 187_040],
    [1997, "Q1", 2, "M", 598_696, 196_224],
    [1997, "Q1", 3, "F", 726_144, 236_344],
    [1997, "Q1", 3, "M", 743_628, 241_676],
    [1997, "Q2", 4, "F", 599_400, 195_060],
    [1997, "Q2", 4, "M", 611_340, 200_340],
    [1997, "Q2", 5, "F", 653_232, 213_156],
    [1997, "Q2", 5, "M", 653_790, 212_536],
    [1997, "Q2", 6, "F", 627_960, 203_280],
    [1997, "Q2", 6, "M", 653_040, 211_440],
    [1997, "Q3", 7, "F", 734_452, 240_622],
    [1997, "Q3", 7, "M", 738_854, 240_002],
    [1997, "Q3", 8, "F", 646_040, 209_746],
    [1997, "Q3", 8, "M", 699_174, 226_610],
    [1997, "Q3", 9, "F", 619_980, 204_060],
    [1997, "Q3", 9, "M", 603_300, 195_720],
    [1997, "Q4", 10, "F", 589_372, 191_146],
    [1997, "Q4", 10, "M", 648_024, 210_552],
    [1997, "Q4", 11, "F", 739_200, 240_780],
    [1997, "Q4", 11, "M", 777_000, 253_140],
    [1997, "Q4", 12, "F", nil, 267_406],
    [1997, "Q4", 12, "M", nil, 273_048]
  ].freeze

  # Schema for the ExtraCol cube, matching ExplicitRecognizerTest.setupMultiColDimCube
  # with arguments: aggName="", yearCols='column="the_year"', qtrCols='column="quarter"',
  # monthCols='column="month_of_year"', monthProp="", defaultMeasure="Unit Sales"
  EXTRA_COL_SCHEMA = <<~XML
    <?xml version="1.0"?>
    <Schema name="FoodMart">
      <Dimension name="Store">
        <Hierarchy hasAll="true" primaryKey="store_id">
          <Table name="store"/>
          <Level name="Store Country" column="store_country" uniqueMembers="true"/>
          <Level name="Store State" column="store_state" uniqueMembers="true"/>
          <Level name="Store City" column="store_city" uniqueMembers="false"/>
          <Level name="Store Name" column="store_name" uniqueMembers="true">
            <Property name="Street address" column="store_street_address" type="String"/>
          </Level>
        </Hierarchy>
      </Dimension>
      <Dimension name="Product">
        <Hierarchy hasAll="true" primaryKey="product_id" primaryKeyTable="product">
          <Join leftKey="product_class_id" rightKey="product_class_id">
            <Table name="product"/>
            <Table name="product_class"/>
          </Join>
          <Level name="Product Family" table="product_class" column="product_family"
              uniqueMembers="true"/>
          <Level name="Product Department" table="product_class" column="product_department"
              uniqueMembers="false"/>
          <Level name="Product Category" table="product_class" column="product_category"
              uniqueMembers="false"/>
        </Hierarchy>
      </Dimension>
      <Cube name="ExtraCol" defaultMeasure="Unit Sales">
        <Table name="sales_fact_1997">
        </Table>
        <Dimension name="TimeExtra" foreignKey="time_id">
          <Hierarchy hasAll="false" primaryKey="time_id">
            <Table name="time_by_day"/>
            <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true"
                levelType="TimeYears"/>
            <Level name="Quarter" column="quarter" uniqueMembers="false"
                levelType="TimeQuarters"/>
            <Level name="Month" column="month_of_year" uniqueMembers="false" type="Numeric"
                levelType="TimeMonths"/>
          </Hierarchy>
        </Dimension>
        <Dimension name="Gender" foreignKey="customer_id">
          <Hierarchy hasAll="true" primaryKey="customer_id">
            <Table name="customer"/>
            <Level name="Gender" column="gender" uniqueMembers="true"/>
          </Hierarchy>
        </Dimension>
        <DimensionUsage name="Store" source="Store" foreignKey="store_id"/>
        <DimensionUsage name="Product" source="Product" foreignKey="product_id"/>
        <Measure name="Unit Sales" column="unit_sales" aggregator="sum"
            formatString="Standard" visible="false"/>
        <Measure name="Avg Unit Sales" column="unit_sales" aggregator="avg"
            formatString="Standard" visible="false"/>
        <Measure name="Store Cost" column="store_cost" aggregator="sum"
            formatString="#,###.00"/>
        <Measure name="Customer Count" column="customer_id" aggregator="distinct-count" formatString="#,###"/>
      </Cube>
    </Schema>
  XML

  def create_agg_table(jdbc_connection)
    statement = jdbc_connection.createStatement

    statement.executeUpdate(<<~SQL)
      CREATE TABLE #{AGG_TABLE_NAME} (
        the_year INTEGER,
        quarter VARCHAR(30),
        month_of_year INTEGER,
        gender VARCHAR(30),
        unit_sales INTEGER,
        fact_count INTEGER
      )
    SQL

    AGG_TABLE_DATA.each do |row|
      unit_sales = row[4].nil? ? "NULL" : row[4]
      statement.executeUpdate(
        "INSERT INTO #{AGG_TABLE_NAME} VALUES (#{row[0]}, '#{row[1]}', #{row[2]}, '#{row[3]}', #{unit_sales}, #{row[5]})"
      )
    end

    statement.close
  end

  def drop_agg_table(jdbc_connection)
    statement = jdbc_connection.createStatement
    begin
      statement.executeUpdate("DROP TABLE #{AGG_TABLE_NAME}")
    rescue java.sql.SQLException
      # Ignore errors during cleanup
    end
    statement.close
  end

  def create_extra_col_connection
    Mondrian::OLAP::Connection.flush_schema_cache
    params = CONNECTION_PARAMS.merge(catalog_content: EXTRA_COL_SCHEMA)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  before(:all) do
    # Obtain a JDBC connection via a temporary Mondrian connection
    temp_olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
    @jdbc_connection = temp_olap.raw_mondrian_connection.getDataSource.getConnection
    temp_olap.close
    create_agg_table(@jdbc_connection)
  end

  after(:all) do
    drop_agg_table(@jdbc_connection)
    @jdbc_connection&.close
  end

  # Java: AggregationOverAggTableTest#testAvgMeasureLowestGranularity
  it "avg measure at lowest granularity" do
    with_properties(
      EnableNativeCrossJoin: true,
      EnableNativeNonEmpty: true,
      GenerateFormattedSql: true,
      DisableCaching: true,
      UseAggregates: true,
      ReadAggregates: true
    ) do
      olap = create_extra_col_connection
      begin
        mdx = <<~MDX.chomp
          select {[Measures].[Avg Unit Sales]} on columns, non empty CrossJoin({[TimeExtra].[1997].[Q1].Children},{[Gender].[M]}) on rows from [ExtraCol]
        MDX

        assert_query_returns olap, mdx, <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Avg Unit Sales]}
          Axis #2:
          {[TimeExtra].[1997].[Q1].[1], [Gender].[M]}
          {[TimeExtra].[1997].[Q1].[2], [Gender].[M]}
          {[TimeExtra].[1997].[Q1].[3], [Gender].[M]}
          Row #0: 3
          Row #1: 3
          Row #2: 3
        RESULT

        # SQL assertion is MySQL-specific, matching the Java mysqlPattern
        if MONDRIAN_DRIVER == "mysql"
          queries = capture_sql { olap.execute(mdx) }
          agg_query = queries.detect { |q| q.include?(AGG_TABLE_NAME) }
          assert agg_query, "Expected SQL against #{AGG_TABLE_NAME}"

          expected_sql = <<~SQL.chomp
            select
                `agg_c_avg_sales_fact_1997`.`the_year` as `c0`,
                `agg_c_avg_sales_fact_1997`.`quarter` as `c1`,
                `agg_c_avg_sales_fact_1997`.`month_of_year` as `c2`,
                `agg_c_avg_sales_fact_1997`.`gender` as `c3`,
                (`agg_c_avg_sales_fact_1997`.`unit_sales`) / (`agg_c_avg_sales_fact_1997`.`fact_count`) as `m0`
            from
                `agg_c_avg_sales_fact_1997` as `agg_c_avg_sales_fact_1997`
            where
                `agg_c_avg_sales_fact_1997`.`the_year` = 1997
            and
                `agg_c_avg_sales_fact_1997`.`quarter` = 'Q1'
            and
                `agg_c_avg_sales_fact_1997`.`month_of_year` in (1, 2, 3)
            and
                `agg_c_avg_sales_fact_1997`.`gender` = 'M'
          SQL

          assert_like expected_sql, agg_query
        end
      ensure
        olap&.close
        Mondrian::OLAP::Connection.flush_schema_cache
      end
    end
  end
end
