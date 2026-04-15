# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Custom tables and data matching mondrian_2225.csv used by both
# AggregationOnInvalidRoleTest and AggregationOnInvalidRoleWhenNotIgnoringTest.
MONDRIAN_2225_TABLES = %w[mondrian2225_fact mondrian2225_agg mondrian2225_customer mondrian2225_dim].freeze

MONDRIAN_2225_CUBE = <<~XML
  <Cube name="mondrian2225" visible="true" cache="true" enabled="true">
    <Table name="mondrian2225_fact">
      <AggName name="mondrian2225_agg" ignorecase="true">
        <AggFactCount column="fact_count"/>
        <AggMeasure column="fact_measure" name="[Measures].[Measure]"/>
        <AggLevel column="dim_code" name="[Product Code].[Code]" collapsed="true"/>
      </AggName>
    </Table>
    <Dimension type="StandardDimension" visible="true" foreignKey="customer_id" highCardinality="false" name="Customer">
      <Hierarchy name="Customer" visible="true" hasAll="true" primaryKey="customer_id">
        <Table name="mondrian2225_customer"/>
        <Level name="First Name" visible="true" column="customer_name" type="String" uniqueMembers="false" levelType="Regular" hideMemberIf="Never"/>
      </Hierarchy>
    </Dimension>
    <Dimension type="StandardDimension" visible="true" foreignKey="product_id" highCardinality="false" name="Product Code">
      <Hierarchy name="Product Code" visible="true" hasAll="true" primaryKey="product_id">
        <Table name="mondrian2225_dim"/>
        <Level name="Code" visible="true" column="product_code" type="String" uniqueMembers="false" levelType="Regular" hideMemberIf="Never"/>
      </Hierarchy>
    </Dimension>
    <Measure name="Measure" column="fact" aggregator="sum" visible="true"/>
  </Cube>
XML

MONDRIAN_2225_ROLE = <<~XML
  <Role name="Test">
    <SchemaGrant access="none">
      <CubeGrant cube="mondrian2225" access="all">
        <HierarchyGrant hierarchy="[Customer.Customer]" topLevel="[Customer.Customer].[First Name]" access="custom">
          <MemberGrant member="[Customer.Customer].[NonExistingName]" access="all"/>
        </HierarchyGrant>
      </CubeGrant>
    </SchemaGrant>
  </Role>
XML

MONDRIAN_2225_ANALYZER_QUERY = <<~MDX.chomp
  with
    set [*NATIVE_CJ_SET_WITH_SLICER] as 'Filter([*BASE_MEMBERS__Product Code_], (NOT IsEmpty([Measures].[Measure])))'
    set [*NATIVE_CJ_SET] as '[*NATIVE_CJ_SET_WITH_SLICER]'
    set [*BASE_MEMBERS__Product Code_] as '[Product Code].[Code].Members'
    set [*BASE_MEMBERS__Measures_] as '{[Measures].[Measure]}'
    set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {[Product Code].CurrentMember})'
    set [*SORTED_ROW_AXIS] as 'Order([*CJ_ROW_AXIS], [Product Code].CurrentMember.OrderKey, BASC)'
  select
    [*BASE_MEMBERS__Measures_] on columns,
    [*SORTED_ROW_AXIS] on rows
  from [mondrian2225]
MDX

def create_mondrian_2225_tables(jdbc_connection)
  statement = jdbc_connection.createStatement

  # Fact table
  statement.executeUpdate("CREATE TABLE mondrian2225_fact (product_id INTEGER, customer_id INTEGER, fact INTEGER)")
  [
    [1, 1, 1], [2, 2, 2], [3, 3, 3], [4, 4, 4], [5, 5, 5],
    [6, 5, 6], [7, 5, 7], [8, 5, 8], [9, 5, 9], [10, 5, 10]
  ].each do |row|
    statement.executeUpdate("INSERT INTO mondrian2225_fact VALUES (#{row.join(', ')})")
  end

  # Aggregate table
  statement.executeUpdate(
    "CREATE TABLE mondrian2225_agg (dim_code VARCHAR(45), fact_measure DECIMAL(10,2), fact_count INTEGER)"
  )
  [
    %w[eight 175 14], %w[five 5 1], %w[four 4 1],
    %w[mdg 2 1], %w[tst 1000 1], %w[three 3 1], %w[two 2 1]
  ].each do |row|
    statement.executeUpdate("INSERT INTO mondrian2225_agg VALUES ('#{row[0]}', #{row[1]}, #{row[2]})")
  end

  # Customer dimension table
  statement.executeUpdate("CREATE TABLE mondrian2225_customer (customer_id INTEGER, customer_name VARCHAR(45))")
  (1..8).each do |i|
    statement.executeUpdate("INSERT INTO mondrian2225_customer VALUES (#{i}, 'Name#{i}')")
  end

  # Product dimension table
  statement.executeUpdate(
    "CREATE TABLE mondrian2225_dim (product_id INTEGER, product_code VARCHAR(45), product_sub_code VARCHAR(45))"
  )
  [
    [1, 'mdg', 'mdg'], [2, 'two', 'second'], [3, 'three', 'third'],
    [4, 'four', 'fourth'], [5, 'five', 'fifth'], [6, 'tst', 'tstth'],
    [7, 'seven', 'seventh'], [8, 'eight', 'eighth'], [9, 'nine', 'ninth'],
    [10, 'ten', 'tenth']
  ].each do |row|
    statement.executeUpdate("INSERT INTO mondrian2225_dim VALUES (#{row[0]}, '#{row[1]}', '#{row[2]}')")
  end

  statement.close
end

def drop_mondrian_2225_tables(jdbc_connection)
  statement = jdbc_connection.createStatement
  MONDRIAN_2225_TABLES.each do |table|
    begin
      statement.executeUpdate("DROP TABLE #{table}")
    rescue java.sql.SQLException
      # Ignore errors during cleanup
    end
  end
  statement.close
end

def build_mondrian_2225_schema(cube_xml, role_xml)
  schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
  schema = schema.sub("</Schema>", "#{role_xml}</Schema>")
  schema
end

# Java: mondrian/rolap/agg/AggregationOnInvalidRoleTest.java
describe "AggregationOnInvalidRole" do
  before(:all) do
    # Obtain a JDBC connection via a temporary Mondrian connection
    temp_olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
    @jdbc_connection = temp_olap.raw_mondrian_connection.getDataSource.getConnection
    temp_olap.close
    create_mondrian_2225_tables(@jdbc_connection)
  end

  after(:all) do
    drop_mondrian_2225_tables(@jdbc_connection)
    @jdbc_connection&.close
  end

  # Java: AggregationOnInvalidRoleTest#test_ExecutesCorrectly_WhenIgnoringInvalidMembers
  it "executes correctly when ignoring invalid members" do
    with_properties(UseAggregates: true, ReadAggregates: true, IgnoreInvalidMembers: true) do
      Mondrian::OLAP::Connection.flush_schema_cache
      schema = build_mondrian_2225_schema(MONDRIAN_2225_CUBE, MONDRIAN_2225_ROLE)
      params = CONNECTION_PARAMS.merge(catalog_content: schema, role: "Test")
      params.delete(:catalog)
      olap = Mondrian::OLAP::Connection.create(params)
      begin
        assert_query_returns olap, MONDRIAN_2225_ANALYZER_QUERY, <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Measure]}
          Axis #2:
          {[Product Code].[eight]}
          {[Product Code].[five]}
          {[Product Code].[four]}
          {[Product Code].[mdg]}
          {[Product Code].[three]}
          {[Product Code].[tst]}
          {[Product Code].[two]}
          Row #0: 175
          Row #1: 5
          Row #2: 4
          Row #3: 2
          Row #4: 3
          Row #5: 1,000
          Row #6: 2
        RESULT
      ensure
        olap.close
        Mondrian::OLAP::Connection.flush_schema_cache
      end
    end
  end
end
