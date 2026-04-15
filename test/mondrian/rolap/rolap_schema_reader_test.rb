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

# Java: mondrian/rolap/RolapSchemaReaderTest.java
describe "RolapSchemaReader" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  private

  # Build a Util.PropertyList equivalent to what TestContext.getConnectionProperties()
  # returns for the current test environment.
  def build_connection_properties
    properties = Java::MondrianOlap::Util::PropertyList.new
    properties.put("Provider", "mondrian")
    properties.put("Jdbc", DATABASE_JDBC_URL)
    properties.put("JdbcUser", DATABASE_USER)
    properties.put("JdbcPassword", DATABASE_PASSWORD)
    properties.put("JdbcDrivers", JDBC_DRIVER)
    properties.put("Catalog", CATALOG_FILE)
    properties
  end

  # Create a connection with a given role using the FoodMart schema.
  def connection_with_role(role_name)
    Mondrian::OLAP::Connection.create(
      CONNECTION_PARAMS.merge(role: role_name)
    )
  end

  # Create a connection with a custom role added to the FoodMart schema.
  def connection_with_custom_role(role_xml, role_name)
    schema = SchemaHelper::FOODMART_SCHEMA.sub("</Schema>", "#{role_xml}\n</Schema>")
    params = CONNECTION_PARAMS.merge(catalog_content: schema, role: role_name)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  # Assert that all cube names exist in the expected list.
  def assert_cube_exists(expected_cubes, cubes)
    cubes.each do |cube|
      cube_name = cube.getName
      assert expected_cubes.include?(cube_name),
        "Cube name not found: #{cube_name}"
    end
  end

  public

  describe "getCubes" do
    # Java: RolapSchemaReaderTest#testGetCubesWithNoHrCubes
    it "returns cubes excluding HR when using No HR Cube role" do
      expected_cubes = %w[Sales Warehouse Store] + ["Warehouse and Sales", "Sales Ragged", "Sales 2"]

      olap = connection_with_role("No HR Cube")
      begin
        reader = olap.raw_mondrian_connection.getSchemaReader.withLocus
        cubes = reader.getCubes

        assert_equal expected_cubes.length, cubes.length
        assert_cube_exists(expected_cubes, cubes)
      ensure
        olap.close
      end
    end

    # Java: RolapSchemaReaderTest#testGetCubesWithNoRole
    it "returns all cubes with no role" do
      expected_cubes = %w[Sales Warehouse Store HR] + ["Warehouse and Sales", "Sales Ragged", "Sales 2"]

      reader = @olap.raw_mondrian_connection.getSchemaReader.withLocus
      cubes = reader.getCubes

      assert_equal expected_cubes.length, cubes.length
      assert_cube_exists(expected_cubes, cubes)
    end

    # Java: RolapSchemaReaderTest#testGetCubesForCaliforniaManager
    it "returns only Sales cube for California manager role" do
      expected_cubes = %w[Sales]

      olap = connection_with_role("California manager")
      begin
        reader = olap.raw_mondrian_connection.getSchemaReader.withLocus
        cubes = reader.getCubes

        assert_equal expected_cubes.length, cubes.length
        assert_cube_exists(expected_cubes, cubes)
      ensure
        olap.close
      end
    end
  end

  describe "UseContentChecksum" do
    # Java: RolapSchemaReaderTest#testConnectUseContentChecksum
    it "connects successfully with UseContentChecksum enabled" do
      properties = build_connection_properties
      properties.put(
        Java::MondrianRolap::RolapConnectionProperties::UseContentChecksum.name,
        "true"
      )

      connection = Java::MondrianOlap::DriverManager.getConnection(properties, nil)
      refute_nil connection
      connection.close
    end
  end

  describe "getCubeDimensions" do
    # With SsasCompatibleNaming=false (default):
    # hierarchyName("Time", "Weekly") => "[Time.Weekly]"
    # hierarchyName("Time", "Time")   => "[Time]"
    TIME_WEEKLY = "[Time.Weekly]"
    TIME_TIME = "[Time]"

    # Java: RolapSchemaReaderTest#testGetCubeDimensions
    it "enforces access control on getCubeDimensions and getDimensionHierarchies" do
      role_xml = <<~XML
        <Role name="REG1">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <DimensionGrant dimension="Store" access="none"/>
              <HierarchyGrant hierarchy="#{TIME_TIME}" access="none"/>
              <HierarchyGrant hierarchy="#{TIME_WEEKLY}" access="all"/>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML

      olap = connection_with_custom_role(role_xml, "REG1")
      begin
        reader = olap.raw_mondrian_connection.getSchemaReader.withLocus

        # Verify cube access
        cubes = {}
        reader.getCubes.each { |cube| cubes[cube.getName] = cube }
        assert_equal true, cubes.key?("Sales")       # granted access
        assert_equal false, cubes.key?("HR")          # denied access
        assert_equal false, cubes.key?("Bad")         # does not exist

        sales_cube = cubes["Sales"]

        # Verify dimension access
        dimensions = {}
        hierarchies = {}
        reader.getCubeDimensions(sales_cube).each do |dimension|
          dimensions[dimension.getName] = dimension
          reader.getDimensionHierarchies(dimension).each do |hierarchy|
            hierarchies[hierarchy.getUniqueName] = hierarchy
          end
        end

        assert_equal false, dimensions.key?("Store")          # denied access
        assert_equal true, dimensions.key?("Marital Status")  # implicit
        assert_equal true, dimensions.key?("Time")            # implicit
        assert_equal false, dimensions.key?("Bad dimension")  # does not exist

        assert_equal false, hierarchies.key?("[Foo]")
        assert_equal true, hierarchies.key?("[Product]")
        assert_equal true, hierarchies.key?(TIME_WEEKLY)
        assert_equal false, hierarchies.key?("[Time]")
        assert_equal false, hierarchies.key?("[Time].[Time]")
      ensure
        olap.close
      end
    end
  end
end
