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

# Java: mondrian/olap/HierarchyBugTest.java
describe "HierarchyBug" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Execute MDX using Mondrian's internal API, returns mondrian.olap.Result
  def execute_internal_query(olap, mdx)
    connection = olap.raw_mondrian_connection
    query = connection.parseQuery(mdx)
    connection.execute(query)
  end

  # Execute MDX using olap4j API, returns CellSet
  def execute_olap4j_query(olap, mdx)
    statement = olap.raw_connection.createStatement
    statement.executeOlapQuery(mdx)
  end

  # Verify measure axis member's hierarchy unique name (internal API)
  def verify_measure_axis_hierarchy_name(axis, expected)
    unit_sales = axis.getPositions.get(0).get(0)
    hierarchy_name = unit_sales.getHierarchy.getUniqueName
    assert_equal expected, hierarchy_name
  end

  # Verify dimension axis member's hierarchy matches level's hierarchy (internal API).
  # This is the core MONDRIAN-1126 check: member.getHierarchy and level.getHierarchy
  # must return the same unique name.
  def verify_dimension_axis_hierarchy_name(axis, expected)
    year_1997 = axis.getPositions.get(0).get(0)
    member_hierarchy_name = year_1997.getHierarchy.getUniqueName
    assert_equal expected, member_hierarchy_name

    year_level = year_1997.getLevel
    level_hierarchy_name = year_level.getHierarchy.getUniqueName
    assert_equal member_hierarchy_name, level_hierarchy_name
  end

  # Verify member/level hierarchy name identity via olap4j API
  def verify_olap4j_hierarchy_name(cell_set, expected)
    positions = cell_set.getAxes.get(1).getPositions
    year_1997 = positions.get(0).getMembers.get(0)
    member_hierarchy_name = year_1997.getHierarchy.getUniqueName
    assert_equal expected, member_hierarchy_name

    year_level = year_1997.getLevel
    level_hierarchy_name = year_level.getHierarchy.getUniqueName
    assert_equal member_hierarchy_name, level_hierarchy_name
  end

  # Create a fresh connection with SsasCompatibleNaming enabled.
  # Yields the connection and ensures cleanup.
  def with_ssas_connection
    with_properties(SsasCompatibleNaming: true) do
      Mondrian::OLAP::Connection.flush_schema_cache
      olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        yield olap
      ensure
        olap.close
        Mondrian::OLAP::Connection.flush_schema_cache
      end
    end
  end

  def date_dimension_xml
    <<~XML
      <Dimension name="Date" type="TimeDimension" foreignKey="time_id">
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
    XML
  end

  def date_weekly_dimension_xml
    <<~XML
      <Dimension name="Date" type="TimeDimension" foreignKey="time_id">
          <Hierarchy hasAll="true" name="Weekly" primaryKey="time_id">
            <Table name="time_by_day"/>
            <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true"
                levelType="TimeYears"/>
            <Level name="Week" column="week_of_year" type="Numeric" uniqueMembers="false"
                levelType="TimeWeeks"/>
            <Level name="Day" column="day_of_month" uniqueMembers="false" type="Numeric"
                levelType="TimeDays"/>
          </Hierarchy>
        </Dimension>
    XML
  end

  # Java: HierarchyBugTest#testNoHierarchy
  # When using Crossjoin with Time dimension, hierarchies on axes must not be null.
  it "all hierarchies on query axes are non-null" do
    mdx = "select NON EMPTY " \
      "Crossjoin(Hierarchize(Union({[Time].[Time].LastSibling}, " \
      "[Time].[Time].LastSibling.Children)), " \
      "{[Measures].[Unit Sales], " \
      "[Measures].[Store Cost]}) ON columns, " \
      "NON EMPTY Hierarchize(Union({[Store].[All Stores]}, " \
      "[Store].[All Stores].Children)) ON rows " \
      "from [Sales]"

    connection = @olap.raw_mondrian_connection
    query = connection.parseQuery(mdx)

    query.getAxes.length.times do |i|
      ordinal = Java::MondrianOlap::AxisOrdinal::StandardAxisOrdinal.forLogicalOrdinal(i)
      hierarchies = query.getMdxHierarchiesOnAxis(ordinal)
      next if hierarchies.nil?

      hierarchies.each do |hierarchy|
        refute_nil hierarchy, "Got a null Hierarchy, Should be Time Hierarchy"
      end
    end
  end

  # MONDRIAN-1126: member.getHierarchy vs level.getHierarchy differences in Time Dimension
  describe "MONDRIAN-1126: member vs level hierarchy name identity" do
    describe "internal API" do
      # Java: HierarchyBugTest#testNamesIdentitySsasCompatibleTimeHierarchy
      it "SSAS compatible Time hierarchy" do
        mdx = <<~MDX
          SELECT
             [Measures].[Unit Sales] ON COLUMNS,
             [Time].[Time].[Year].Members ON ROWS
          FROM [Sales]
        MDX
        with_ssas_connection do |olap|
          result = execute_internal_query(olap, mdx)
          verify_measure_axis_hierarchy_name(result.getAxes[0], "[Measures]")
          verify_dimension_axis_hierarchy_name(result.getAxes[1], "[Time]")
        end
      end

      # Java: HierarchyBugTest#testNamesIdentitySsasCompatibleWeeklyHierarchy
      it "SSAS compatible Weekly hierarchy" do
        mdx = <<~MDX
          SELECT
             [Measures].[Unit Sales] ON COLUMNS,
             [Time].[Weekly].[Year].Members ON ROWS
          FROM [Sales]
        MDX
        with_ssas_connection do |olap|
          result = execute_internal_query(olap, mdx)
          verify_measure_axis_hierarchy_name(result.getAxes[0], "[Measures]")
          verify_dimension_axis_hierarchy_name(result.getAxes[1], "[Time].[Weekly]")
        end
      end

      # Java: HierarchyBugTest#testNamesIdentitySsasInCompatibleTimeHierarchy
      it "SSAS incompatible Time hierarchy" do
        mdx = <<~MDX
          SELECT
             [Measures].[Unit Sales] ON COLUMNS,
             [Time].[Year].Members ON ROWS
          FROM [Sales]
        MDX
        result = execute_internal_query(@olap, mdx)
        verify_measure_axis_hierarchy_name(result.getAxes[0], "[Measures]")
        verify_dimension_axis_hierarchy_name(result.getAxes[1], "[Time]")
      end

      # Java: HierarchyBugTest#testNamesIdentitySsasInCompatibleWeeklyHierarchy
      it "SSAS incompatible Weekly hierarchy" do
        mdx = <<~MDX
          SELECT
             [Measures].[Unit Sales] ON COLUMNS,
             [Time.Weekly].[Year].Members ON ROWS
          FROM [Sales]
        MDX
        result = execute_internal_query(@olap, mdx)
        verify_measure_axis_hierarchy_name(result.getAxes[0], "[Measures]")
        verify_dimension_axis_hierarchy_name(result.getAxes[1], "[Time.Weekly]")
      end
    end

    describe "olap4j API" do
      # Java: HierarchyBugTest#testNamesIdentitySsasCompatibleOlap4j
      # Essential: Time hierarchy has hasAll="false", so we expect "[Time]"
      it "SSAS compatible Time hierarchy" do
        mdx = <<~MDX
          SELECT
             [Measures].[Unit Sales] ON COLUMNS,
             [Time].[Time].[Year].Members ON ROWS
          FROM [Sales]
        MDX
        with_ssas_connection do |olap|
          cell_set = execute_olap4j_query(olap, mdx)
          verify_olap4j_hierarchy_name(cell_set, "[Time]")
        end
      end

      # Java: HierarchyBugTest#testNamesIdentitySsasInCompatibleOlap4j
      it "SSAS incompatible Time hierarchy" do
        mdx = <<~MDX
          SELECT
             [Measures].[Unit Sales] ON COLUMNS,
             [Time].[Time].[Year].Members ON ROWS
          FROM [Sales]
        MDX
        cell_set = execute_olap4j_query(@olap, mdx)
        verify_olap4j_hierarchy_name(cell_set, "[Time]")
      end

      # Java: HierarchyBugTest#testNamesIdentitySsasCompatibleOlap4jWeekly
      it "SSAS compatible Weekly hierarchy" do
        mdx = <<~MDX
          SELECT
             [Measures].[Unit Sales] ON COLUMNS,
             [Time].[Weekly].[Year].Members ON ROWS
          FROM [Sales]
        MDX
        with_ssas_connection do |olap|
          cell_set = execute_olap4j_query(olap, mdx)
          verify_olap4j_hierarchy_name(cell_set, "[Time].[Weekly]")
        end
      end

      # Java: HierarchyBugTest#testNamesIdentitySsasInCompatibleOlap4jWeekly
      it "SSAS incompatible Weekly hierarchy" do
        mdx = <<~MDX
          SELECT
             [Measures].[Unit Sales] ON COLUMNS,
             [Time.Weekly].[Year].Members ON ROWS
          FROM [Sales]
        MDX
        cell_set = execute_olap4j_query(@olap, mdx)
        verify_olap4j_hierarchy_name(cell_set, "[Time.Weekly]")
      end

      describe "with Date dimension" do
        # Java: HierarchyBugTest#testNamesIdentitySsasCompatibleOlap4jDateDim
        it "SSAS compatible Date dimension" do
          mdx = <<~MDX
            SELECT
               [Measures].[Unit Sales] ON COLUMNS,
               [Date].[Date].[Year].Members ON ROWS
            FROM [Sales]
          MDX
          with_properties(SsasCompatibleNaming: true) do
            Mondrian::OLAP::Connection.flush_schema_cache
            olap = connection_with_modified_cube("Sales", dimensions: date_dimension_xml)
            begin
              cell_set = execute_olap4j_query(olap, mdx)
              verify_olap4j_hierarchy_name(cell_set, "[Date]")
            ensure
              olap.close
              Mondrian::OLAP::Connection.flush_schema_cache
            end
          end
        end

        # Java: HierarchyBugTest#testNamesSsasInCompatibleOlap4jDateDim
        it "SSAS incompatible Date dimension" do
          mdx = <<~MDX
            SELECT
               [Measures].[Unit Sales] ON COLUMNS,
               [Date].[Date].[Year].Members ON ROWS
            FROM [Sales]
          MDX
          olap = connection_with_modified_cube("Sales", dimensions: date_dimension_xml)
          begin
            cell_set = execute_olap4j_query(olap, mdx)
            verify_olap4j_hierarchy_name(cell_set, "[Date]")
          ensure
            olap.close
          end
        end

        # Java: HierarchyBugTest#testNamesIdentitySsasCompatibleOlap4jDateWeekly
        it "SSAS compatible Date Weekly hierarchy" do
          mdx = <<~MDX
            SELECT
               [Measures].[Unit Sales] ON COLUMNS,
               [Date].[Weekly].[Year].Members ON ROWS
            FROM [Sales]
          MDX
          with_properties(SsasCompatibleNaming: true) do
            Mondrian::OLAP::Connection.flush_schema_cache
            olap = connection_with_modified_cube("Sales", dimensions: date_weekly_dimension_xml)
            begin
              cell_set = execute_olap4j_query(olap, mdx)
              verify_olap4j_hierarchy_name(cell_set, "[Date].[Weekly]")
            ensure
              olap.close
              Mondrian::OLAP::Connection.flush_schema_cache
            end
          end
        end

        # Java: HierarchyBugTest#testNamesIdentitySsasInCompatibleOlap4jDateDim
        it "SSAS incompatible Date Weekly hierarchy" do
          mdx = <<~MDX
            SELECT
               [Measures].[Unit Sales] ON COLUMNS,
               [Date.Weekly].[Year].Members ON ROWS
            FROM [Sales]
          MDX
          olap = connection_with_modified_cube("Sales", dimensions: date_weekly_dimension_xml)
          begin
            cell_set = execute_olap4j_query(olap, mdx)
            verify_olap4j_hierarchy_name(cell_set, "[Date.Weekly]")
          ensure
            olap.close
          end
        end
      end
    end
  end
end
