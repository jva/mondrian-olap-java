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

# Java: mondrian/rolap/RolapResultTest.java
describe "RolapResult" do
  # The first three tests (testAll, testD1, testD2) require custom tables
  # loaded from RolapResultTest.csv. We create them via JDBC and build a
  # custom schema with cube definitions matching the Java test.
  describe "custom cube tests" do
    before(:all) do
      # Create a temporary olap connection to get a JDBC connection
      # from the Mondrian data source, avoiding JRuby classloader issues.
      temp_olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      @jdbc_connection = temp_olap.raw_mondrian_connection.getDataSource.getConnection
      temp_olap.close
      create_custom_tables
      create_custom_olap_connection
    end

    after(:all) do
      @custom_olap&.close
      drop_custom_tables
      @jdbc_connection&.close
    end

    RESULTS_ALL = <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[D1].[a]}
      {[D1].[b]}
      {[D1].[c]}
      Axis #2:
      {[D2].[x]}
      {[D2].[y]}
      {[D2].[z]}
      Row #0: 5
      Row #0:
      Row #0:
      Row #1:
      Row #1: 10
      Row #1:
      Row #2:
      Row #2:
      Row #2: 15
    RESULT

    RESULTS = <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[D1].[a]}
      {[D1].[b]}
      {[D1].[c]}
      Axis #2:
      {[D2].[x]}
      {[D2].[y]}
      {[D2].[z]}
      Row #0: 5
      Row #0:
      Row #0:
      Row #1:
      Row #1: 10
      Row #1:
      Row #2:
      Row #2:
      Row #2: 15
    RESULT

    # Java: RolapResultTest#testAll
    it "queries FTAll cube with filter" do
      mdx = <<~MDX
        select
          filter({[D1].[a],[D1].[b],[D1].[c]},
            [Measures].[Value] > 0)
          ON COLUMNS,
          {[D2].[x],[D2].[y],[D2].[z]}
          ON ROWS
        from FTAll
      MDX

      assert_query_returns @custom_olap, mdx, RESULTS_ALL
    end

    # Java: RolapResultTest#testD1
    # The Java test executes the query and compares the result string.
    # With hasAll='false' and defaultMember='[D1].[d]', the filter
    # evaluates against the default member context.
    it "queries FT1 cube with filter and non-all default members" do
      mdx = <<~MDX
        select
          filter({[D1].[a],[D1].[b],[D1].[c]},
            [Measures].[Value] > 0)
          ON COLUMNS,
          {[D2].[x],[D2].[y],[D2].[z]}
          ON ROWS
        from FT1
      MDX

      assert_query_returns @custom_olap, mdx, RESULTS
    end

    # Java: RolapResultTest#testD2
    it "queries FT2 cube with NON EMPTY filter" do
      mdx = <<~MDX
        select
          NON EMPTY filter({[D1].[a],[D1].[b],[D1].[c]},
            [Measures].[Value] > 0)
          ON COLUMNS,
          {[D2].[x],[D2].[y],[D2].[z]}
          ON ROWS
        from FT2
      MDX

      assert_query_returns @custom_olap, mdx, RESULTS
    end

    private

    # Table names used for the custom cubes. Lowercase for cross-database
    # compatibility (PostgreSQL lowercases unquoted identifiers).
    CUSTOM_TABLES = %w[ft1 ft2 d1 d2].freeze

    def create_custom_tables
      statement = @jdbc_connection.createStatement

      # Dimension table d1
      statement.executeUpdate("CREATE TABLE d1 (d1_id INTEGER, name VARCHAR(20))")
      statement.executeUpdate("INSERT INTO d1 VALUES (1, 'a')")
      statement.executeUpdate("INSERT INTO d1 VALUES (2, 'b')")
      statement.executeUpdate("INSERT INTO d1 VALUES (3, 'c')")
      statement.executeUpdate("INSERT INTO d1 VALUES (4, 'd')")

      # Dimension table d2
      statement.executeUpdate("CREATE TABLE d2 (d2_id INTEGER, name VARCHAR(20))")
      statement.executeUpdate("INSERT INTO d2 VALUES (1, 'x')")
      statement.executeUpdate("INSERT INTO d2 VALUES (2, 'y')")
      statement.executeUpdate("INSERT INTO d2 VALUES (3, 'z')")
      statement.executeUpdate("INSERT INTO d2 VALUES (4, 'w')")

      # Fact table ft1
      statement.executeUpdate("CREATE TABLE ft1 (d1_id INTEGER, d2_id INTEGER, value DECIMAL(10,2))")
      statement.executeUpdate("INSERT INTO ft1 VALUES (1, 1, 5)")
      statement.executeUpdate("INSERT INTO ft1 VALUES (2, 2, 10)")
      statement.executeUpdate("INSERT INTO ft1 VALUES (3, 3, 15)")

      # Fact table ft2
      statement.executeUpdate("CREATE TABLE ft2 (d1_id INTEGER, d2_id INTEGER, value DECIMAL(10,2), vextra DECIMAL(10,2))")
      statement.executeUpdate("INSERT INTO ft2 VALUES (1, 1, 5, NULL)")
      statement.executeUpdate("INSERT INTO ft2 VALUES (2, 2, 10, NULL)")
      statement.executeUpdate("INSERT INTO ft2 VALUES (3, 3, 15, NULL)")
      statement.executeUpdate("INSERT INTO ft2 VALUES (4, 1, 2, NULL)")
      statement.executeUpdate("INSERT INTO ft2 VALUES (4, 2, 4, NULL)")
      statement.executeUpdate("INSERT INTO ft2 VALUES (4, 3, 8, NULL)")
      statement.executeUpdate("INSERT INTO ft2 VALUES (1, 4, 3, NULL)")
      statement.executeUpdate("INSERT INTO ft2 VALUES (2, 4, 9, NULL)")
      statement.executeUpdate("INSERT INTO ft2 VALUES (3, 4, 27, NULL)")

      statement.close
    end

    def drop_custom_tables
      statement = @jdbc_connection.createStatement
      CUSTOM_TABLES.each do |table|
        begin
          statement.executeUpdate("DROP TABLE #{table}")
        rescue java.sql.SQLException
          # Ignore errors during cleanup
        end
      end
      statement.close
    end

    def create_custom_olap_connection
      cube_xml = <<~XML
        <Cube name="FTAll">
          <Table name="ft1"/>
          <Dimension name="D1" foreignKey="d1_id">
            <Hierarchy hasAll="true" primaryKey="d1_id">
              <Table name="d1"/>
              <Level name="Name" column="name" type="String" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
          <Dimension name="D2" foreignKey="d2_id">
            <Hierarchy hasAll="true" primaryKey="d2_id">
              <Table name="d2"/>
              <Level name="Name" column="name" type="String" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
          <Measure name="Value" column="value" aggregator="sum" formatString="#,###"/>
        </Cube>

        <Cube name="FT1">
          <Table name="ft1"/>
          <Dimension name="D1" foreignKey="d1_id">
            <Hierarchy hasAll="false" defaultMember="[D1].[d]" primaryKey="d1_id">
              <Table name="d1"/>
              <Level name="Name" column="name" type="String" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
          <Dimension name="D2" foreignKey="d2_id">
            <Hierarchy hasAll="false" defaultMember="[D2].[w]" primaryKey="d2_id">
              <Table name="d2"/>
              <Level name="Name" column="name" type="String" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
          <Measure name="Value" column="value" aggregator="sum" formatString="#,###"/>
        </Cube>

        <Cube name="FT2">
          <Table name="ft2"/>
          <Dimension name="D1" foreignKey="d1_id">
            <Hierarchy hasAll="false" defaultMember="[D1].[d]" primaryKey="d1_id">
              <Table name="d1"/>
              <Level name="Name" column="name" type="String" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
          <Dimension name="D2" foreignKey="d2_id">
            <Hierarchy hasAll="false" defaultMember="[D2].[w]" primaryKey="d2_id">
              <Table name="d2"/>
              <Level name="Name" column="name" type="String" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
          <Measure name="Value" column="value" aggregator="sum" formatString="#,###"/>
        </Cube>
      XML

      schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
      params = CONNECTION_PARAMS.merge(catalog_content: schema)
      params.delete(:catalog)
      @custom_olap = Mondrian::OLAP::Connection.create(params)
    end
  end

  describe "FoodMart cube tests" do
    before(:all) do
      create_olap_connection
    end

    after(:all) do
      @olap.close if @olap
    end

    # Java: RolapResultTest#testNonAllPromotionMembers
    it "non-all promotion members with crossjoin" do
      olap = connection_with_modified_cube("Sales",
        dimensions: <<~XML
          <Dimension name="Promotions2" foreignKey="promotion_id">
            <Hierarchy hasAll="false" primaryKey="promotion_id">
              <Table name="promotion"/>
              <Level name="Promotion2 Name" column="promotion_name" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
        XML
      )
      begin
        assert_query_returns olap,
          "select {[Promotion2 Name].[Price Winners], [Promotion2 Name].[Sale Winners]} " \
          "* {Tail([Time].[Year].Members,3)} ON COLUMNS, " \
          "NON EMPTY Crossjoin({[Store].CurrentMember.Children}, " \
          " {[Store Type].[All Store Types].Children}) ON ROWS " \
          "from [Sales]",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Promotions2].[Price Winners], [Time].[1997]}
            {[Promotions2].[Price Winners], [Time].[1998]}
            {[Promotions2].[Sale Winners], [Time].[1997]}
            {[Promotions2].[Sale Winners], [Time].[1998]}
            Axis #2:
            {[Store].[USA], [Store Type].[Mid-Size Grocery]}
            {[Store].[USA], [Store Type].[Small Grocery]}
            {[Store].[USA], [Store Type].[Supermarket]}
            Row #0:
            Row #0:
            Row #0: 444
            Row #0:
            Row #1: 23
            Row #1:
            Row #1:
            Row #1:
            Row #2: 1,271
            Row #2:
            Row #2:
            Row #2:
          RESULT
      ensure
        olap.close
      end
    end
  end
end
