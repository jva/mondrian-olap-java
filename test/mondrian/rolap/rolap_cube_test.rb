# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2001-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapCubeTest.java
describe "RolapCube" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  private

  def internal_connection
    @olap.raw_mondrian_connection
  end

  def lookup_cube(name)
    internal_connection.getSchema.lookupCube(name, false)
  end

  # Look up a member by path segments using a schema reader.
  def lookup_member(schema_reader, *path_segments)
    segments = Java::MondrianOlap::Id::Segment.toList(*path_segments)
    schema_reader.getMemberByUniqueName(segments, true)
  end

  # Find a cube by name from a connection's schema reader.
  def cube_by_name(connection, cube_name)
    schema_reader = connection.getSchemaReader.withLocus
    cubes = schema_reader.getCubes
    cubes.to_a.detect { |c| cube_name == c.getName }
  end

  # Find a dimension by name from an array of dimensions.
  def dimension_with_name(name, dimensions)
    dimensions.to_a.detect { |d| d.getName == name }
  end

  # Build store members for CA and OR (mirrors Java's storeMembersCAAndOR).
  # Java returns a UnaryTupleList; callers apply .slice(0) which for arity-1
  # tuple lists simply returns the underlying List<Member>. Returning a plain
  # Ruby array of members is equivalent.
  def store_members_ca_and_or(schema_reader)
    paths = [
      %w[Store All\ Stores USA CA Alameda],
      %w[Store All\ Stores USA CA Alameda HQ],
      %w[Store All\ Stores USA CA Beverly\ Hills],
      %w[Store All\ Stores USA CA Beverly\ Hills Store\ 6],
      %w[Store All\ Stores USA CA Los\ Angeles],
      %w[Store All\ Stores USA OR Portland],
      %w[Store All\ Stores USA OR Portland Store\ 11],
      %w[Store All\ Stores USA OR Salem],
      %w[Store All\ Stores USA OR Salem Store\ 13]
    ]
    paths.map { |path| lookup_member(schema_reader, *path) }
  end

  # Build warehouse members for Canada, Mexico, USA (mirrors Java's warehouseMembersCanadaMexicoUsa).
  def warehouse_members_canada_mexico_usa(schema_reader)
    [
      lookup_member(schema_reader, "Warehouse", "All Warehouses", "Canada"),
      lookup_member(schema_reader, "Warehouse", "All Warehouses", "Mexico"),
      lookup_member(schema_reader, "Warehouse", "All Warehouses", "USA")
    ]
  end

  # Call Java equals via reflection, bypassing JRuby's dispatch which may not
  # resolve overridden equals correctly on RolapCubeDimension.
  def java_equals(object1, object2)
    equals_method = object1.java_class.getMethod(
      "equals", [java.lang.Object.java_class].to_java(java.lang.Class)
    )
    equals_method.invoke(object1, object2)
  end

  # Call the package-private processFormatStringAttribute method via reflection.
  def invoke_process_format_string_attribute(cube, xml_calc_member, builder)
    method = Java::MondrianRolap::RolapCube.java_class.getDeclaredMethod(
      "processFormatStringAttribute",
      [Java::MondrianOlap::MondrianDef::CalculatedMember.java_class,
       java.lang.StringBuilder.java_class].to_java(java.lang.Class)
    )
    method.setAccessible(true)
    method.invoke(cube, xml_calc_member, builder)
  end

  public

  describe "processFormatStringAttribute" do
    # Java: RolapCubeTest#testProcessFormatStringAttributeToIgnoreNullFormatString
    it "ignores null format string" do
      cube = lookup_cube("Sales")
      builder = java.lang.StringBuilder.new
      invoke_process_format_string_attribute(
        cube, Java::MondrianOlap::MondrianDef::CalculatedMember.new, builder
      )
      assert_equal 0, builder.length
    end

    # Java: RolapCubeTest#testProcessFormatStringAttribute
    it "appends format string attribute" do
      cube = lookup_cube("Sales")
      builder = java.lang.StringBuilder.new
      xml_calc_member = Java::MondrianOlap::MondrianDef::CalculatedMember.new
      format = "FORMAT"
      xml_calc_member.formatString = format
      invoke_process_format_string_attribute(cube, xml_calc_member, builder)

      nl = Java::MondrianOlap::Util.nl
      expected = ",#{nl}FORMAT_STRING = \"#{format}\""
      assert_equal expected, builder.toString
    end
  end

  describe "getCalculatedMembers" do
    # Java: RolapCubeTest#testGetCalculatedMembersWithNoRole
    it "returns all calculated members with no role" do
      expected_names = [
        "[Measures].[Profit]",
        "[Measures].[Average Warehouse Sale]",
        "[Measures].[Profit Growth]",
        "[Measures].[Profit Per Unit Shipped]"
      ]

      connection = internal_connection
      warehouse_and_sales_cube = cube_by_name(connection, "Warehouse and Sales")
      schema_reader = warehouse_and_sales_cube.getSchemaReader(nil)

      calculated_members = schema_reader.getCalculatedMembers
      assert_equal expected_names.length, calculated_members.size

      calculated_member_names = calculated_members.map { |m| m.getUniqueName }
      expected_names.each do |name|
        assert calculated_member_names.include?(name),
          "Calculated member name not found: #{name}"
      end
    end

    # Java: RolapCubeTest#testGetCalculatedMembersForCaliforniaManager
    it "returns calculated members for California manager role" do
      expected_names = [
        "[Measures].[Profit]",
        "[Measures].[Profit last Period]",
        "[Measures].[Profit Growth]"
      ]

      olap = Mondrian::OLAP::Connection.create(
        CONNECTION_PARAMS.merge(role: "California manager")
      )
      begin
        connection = olap.raw_mondrian_connection
        sales_cube = cube_by_name(connection, "Sales")
        schema_reader = sales_cube.getSchemaReader(connection.getRole)

        calculated_members = schema_reader.getCalculatedMembers
        assert_equal expected_names.length, calculated_members.size

        calculated_member_names = calculated_members.map { |m| m.getUniqueName }
        expected_names.each do |name|
          assert calculated_member_names.include?(name),
            "Calculated member name not found: #{name}"
        end
      ensure
        olap.close
      end
    end

    # Java: RolapCubeTest#testGetCalculatedMembersReturnsOnlyAccessibleMembers
    it "returns only accessible members with a role" do
      expected_names = [
        "[Measures].[Profit]",
        "[Measures].[Profit last Period]",
        "[Measures].[Profit Growth]",
        "[Product].[~Missing]"
      ]

      olap = connection_with_additional_members_and_role
      begin
        connection = olap.raw_mondrian_connection
        sales_cube = cube_by_name(connection, "Sales")
        schema_reader = sales_cube.getSchemaReader(connection.getRole)

        calculated_members = schema_reader.getCalculatedMembers
        assert_equal expected_names.length, calculated_members.size

        calculated_member_names = calculated_members.map { |m| m.getUniqueName }
        expected_names.each do |name|
          assert calculated_member_names.include?(name),
            "Calculated member name not found: #{name}"
        end
      ensure
        olap.close
      end
    end

    # Java: RolapCubeTest#testGetCalculatedMembersReturnsOnlyAccessibleMembersForHierarchy
    it "returns only accessible members for a hierarchy" do
      expected_product_names = ["[Product].[~Missing]"]

      olap = connection_with_additional_members_and_role
      begin
        connection = olap.raw_mondrian_connection
        sales_cube = cube_by_name(connection, "Sales")
        schema_reader = sales_cube.getSchemaReader(connection.getRole)

        # Product.~Missing accessible
        product_dim = dimension_with_name("Product", sales_cube.getDimensions)
        calculated_members = schema_reader.getCalculatedMembers(product_dim.getHierarchy)
        assert_equal expected_product_names.length, calculated_members.size

        calculated_member_names = calculated_members.map { |m| m.getUniqueName }
        expected_product_names.each do |name|
          assert calculated_member_names.include?(name),
            "Calculated member name not found: #{name}"
        end

        # Gender.~Missing not accessible
        gender_dim = dimension_with_name("Gender", sales_cube.getDimensions)
        gender_calc_members = schema_reader.getCalculatedMembers(gender_dim.getHierarchy)
        assert_equal 0, gender_calc_members.size
      ensure
        olap.close
      end
    end

    # Java: RolapCubeTest#testGetCalculatedMembersReturnsOnlyAccessibleMembersForLevel
    it "returns only accessible members for a level" do
      expected_product_names = ["[Product].[~Missing]"]

      olap = connection_with_additional_members_and_role
      begin
        connection = olap.raw_mondrian_connection
        sales_cube = cube_by_name(connection, "Sales")
        schema_reader = sales_cube.getSchemaReader(connection.getRole)

        # Product.~Missing accessible
        product_dim = dimension_with_name("Product", sales_cube.getDimensions)
        calculated_members = schema_reader.getCalculatedMembers(product_dim.getHierarchy.getLevels[0])
        assert_equal expected_product_names.length, calculated_members.size

        calculated_member_names = calculated_members.map { |m| m.getUniqueName }
        expected_product_names.each do |name|
          assert calculated_member_names.include?(name),
            "Calculated member name not found: #{name}"
        end

        # Gender.~Missing not accessible
        gender_dim = dimension_with_name("Gender", sales_cube.getDimensions)
        gender_calc_members = schema_reader.getCalculatedMembers(gender_dim.getHierarchy.getLevels[0])
        assert_equal 0, gender_calc_members.size
      ensure
        olap.close
      end
    end
  end

  describe "nonJoiningDimensions" do
    # Java: RolapCubeTest#testNonJoiningDimensions
    it "identifies non-joining dimensions" do
      connection = internal_connection
      sales_cube = cube_by_name(connection, "Sales")
      warehouse_and_sales_cube = cube_by_name(connection, "Warehouse and Sales")
      reader = warehouse_and_sales_cube.getSchemaReader.withLocus

      members = []
      warehouse_members = warehouse_members_canada_mexico_usa(reader)
      warehouse_dim = warehouse_members[0].getDimension
      members.concat(warehouse_members)

      store_members = store_members_ca_and_or(reader)
      store_dim = store_members[0].getDimension
      members.concat(store_members)

      non_joining_dims = sales_cube.nonJoiningDimensions(members.to_java(Java::MondrianOlap::Member))
      assert_equal false, non_joining_dims.contains(store_dim)
      assert_equal true, non_joining_dims.contains(warehouse_dim)
    end
  end

  describe "RolapCubeDimension equality" do
    # Java: RolapCubeTest#testRolapCubeDimensionEquality
    it "dimensions from same cube are equal, from different cubes are not" do
      connection1 = internal_connection

      # Flush the schema cache so connection2 gets an independent schema instance,
      # matching Java's TestContext.instance().withSchema(null).getConnection().
      Mondrian::OLAP::Connection.flush_schema_cache
      olap2 = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        connection2 = olap2.raw_mondrian_connection

        sales_cube1 = cube_by_name(connection1, "Sales")
        reader1 = sales_cube1.getSchemaReader.withLocus
        store_members_sales1 = store_members_ca_and_or(reader1)
        store_dim1 = store_members_sales1[0].getDimension
        assert_equal true, java_equals(store_dim1, store_dim1)

        sales_cube2 = cube_by_name(connection2, "Sales")
        reader2 = sales_cube2.getSchemaReader.withLocus
        store_members_sales2 = store_members_ca_and_or(reader2)
        store_dim2 = store_members_sales2[0].getDimension
        assert_equal true, java_equals(store_dim1, store_dim2)

        warehouse_and_sales_cube = cube_by_name(connection1, "Warehouse and Sales")
        reader_ws = warehouse_and_sales_cube.getSchemaReader.withLocus
        store_members_ws = store_members_ca_and_or(reader_ws)
        store_dim3 = store_members_ws[0].getDimension
        assert_equal false, java_equals(store_dim1, store_dim3)

        warehouse_members = warehouse_members_canada_mexico_usa(reader_ws)
        warehouse_dim = warehouse_members[0].getDimension
        assert_equal false, java_equals(store_dim3, warehouse_dim)
      ensure
        olap2.close
      end
    end
  end

  describe "baseCubes" do
    # Java: RolapCubeTest#testBasedCubesForVirtualCube
    it "returns base cubes for a virtual cube" do
      cube_sales = lookup_cube("Sales")
      cube_warehouse = lookup_cube("Warehouse")
      cube = lookup_cube("Warehouse and Sales")

      refute_nil cube
      refute_nil cube_sales
      refute_nil cube_warehouse
      assert_equal true, cube.isVirtual

      base_cubes = cube.getBaseCubes
      refute_nil base_cubes
      assert_equal 2, base_cubes.size
      assert_same cube_sales, base_cubes.get(0)
      assert_equal cube_warehouse, base_cubes.get(1)
    end

    # Java: RolapCubeTest#testBasedCubesForNotVirtualCubeIsThisCube
    it "returns itself as base cube for a non-virtual cube" do
      cube_sales = lookup_cube("Sales")

      refute_nil cube_sales
      assert_equal false, cube_sales.isVirtual

      base_cubes = cube_sales.getBaseCubes
      refute_nil base_cubes
      assert_equal 1, base_cubes.size
      assert_same cube_sales, base_cubes.get(0)
    end
  end

  private

  # Creates a connection with additional calculated members and the "California manager" role.
  # Mirrors Java's createTestContextWithAdditionalMembersAndARole.
  def connection_with_additional_members_and_role
    non_accessible_member = <<~XML
      <CalculatedMember name="~Missing" dimension="Gender">
        <Formula>100</Formula>
      </CalculatedMember>
    XML
    accessible_member = <<~XML
      <CalculatedMember name="~Missing" dimension="Product">
        <Formula>100</Formula>
      </CalculatedMember>
    XML

    schema = SchemaHelper::FOODMART_SCHEMA.dup
    cube_start = schema.index('<Cube name="Sales"')
    cube_end = schema.index('</Cube>', cube_start)

    # Insert calculated members before </Cube>
    schema = schema[0...cube_end] + non_accessible_member + accessible_member + schema[cube_end..]

    params = CONNECTION_PARAMS.merge(catalog_content: schema, role: "California manager")
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end
end
