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

# Java: mondrian/rolap/RolapCubeHierarchyTest.java
describe "RolapCubeHierarchy" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  private

  # Returns the internal RolapSchema cube by name.
  def lookup_cube(name)
    @olap.raw_mondrian_connection.getSchema.lookupCube(name, true)
  end

  # Returns the first RolapCubeHierarchy for a given dimension name in a cube.
  def find_hierarchy(cube, dimension_name)
    dimension = cube.getDimensions.find { |d| d.getName == dimension_name }
    raise "Dimension #{dimension_name} not found in cube #{cube.getName}" unless dimension
    hierarchy = dimension.getHierarchies[0]
    raise "No hierarchy found for #{dimension_name}" unless hierarchy
    hierarchy
  end

  public

  # Java: RolapCubeHierarchyTest#testMONDRIAN2535
  it "MONDRIAN-2535: query against Warehouse and Sales virtual cube returns correct results" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      Select
        [Customers].children on rows,
        [Gender].children on columns
      From [Warehouse and Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Gender].[F]}
      {[Gender].[M]}
      Axis #2:
      {[Customers].[Canada]}
      {[Customers].[Mexico]}
      {[Customers].[USA]}
      Row #0:
      Row #0:
      Row #1:
      Row #1:
      Row #2: 280,226.21
      Row #2: 285,011.92
    RESULT
  end

  describe "isUsingCubeFact for regular cube" do
    # Java: RolapCubeHierarchyTest#testInit_NoFactCube
    # The Java test exercises the path where factCube is null (or not given), which
    # falls back to cubeDimension.getCube(). The mock cube's getFact() returns null,
    # so usingCubeFact is true. In the real FoodMart schema every non-virtual cube
    # has a non-null fact table, so the null-getFact branch is unreachable without
    # mocking. There is no FoodMart equivalent that isolates factCube=null with a
    # null fact table in a real non-virtual cube — the integration path always hits
    # the getFact().equals() branch instead.
    it "returns false for hierarchy in regular Sales cube where fact table differs from relation" do
      skip "FIXME BY SONNET: Java testInit_NoFactCube asserts isUsingCubeFact==true " \
           "when factCube is null and the fallback cube's getFact() returns null. " \
           "In a real non-virtual FoodMart cube every hierarchy has a non-null fact " \
           "table, so the getFact()==null code path cannot be reached without mocking. " \
           "This test currently verifies a different code path (FactTableDiffers→false) " \
           "and should either be replaced with a proper mock-based unit test or removed " \
           "in favour of the existing FactTableDiffers coverage below."
      sales_cube = lookup_cube("Sales")
      store_hierarchy = find_hierarchy(sales_cube, "Store")

      assert_equal false, store_hierarchy.isUsingCubeFact
    end

    # Java: RolapCubeHierarchyTest#testInit_FactCube_FactTableEquals
    # The Java mock test asserts isUsingCubeFact == true when the fact cube's
    # fact table is the same object as the hierarchy's relation. This corresponds
    # to a degenerate dimension whose levels are defined directly on the fact
    # table with no separate dimension table.
    it "returns true for degenerate dimension where hierarchy relation is the fact table" do
      olap = connection_with_modified_cube("Sales",
        dimensions: <<~XML
          <Dimension name="Degenerate" foreignKey="promotion_id">
            <Hierarchy hasAll="true" primaryKey="promotion_id">
              <Level name="Promotion Id" column="promotion_id" type="Numeric" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
        XML
      )
      begin
        cube = olap.raw_mondrian_connection.getSchema.lookupCube("Sales", true)
        hierarchy = find_hierarchy(cube, "Degenerate")

        assert_equal true, hierarchy.isUsingCubeFact
      ensure
        olap.close
      end
    end
  end

  describe "isUsingCubeFact for virtual cube" do
    # Java: RolapCubeHierarchyTest#testInit_FactCube_NoFactTable
    # Shared dimensions in a virtual cube (no cubeName) use the virtual cube itself
    # as factCube. Since virtual cubes have no fact table (getFact() returns null),
    # isUsingCubeFact is true.
    it "returns true for shared dimension in virtual cube where cube has no fact table" do
      virtual_cube = lookup_cube("Warehouse and Sales")
      store_hierarchy = find_hierarchy(virtual_cube, "Store")
      product_hierarchy = find_hierarchy(virtual_cube, "Product")
      time_hierarchy = find_hierarchy(virtual_cube, "Time")

      assert_equal true, store_hierarchy.isUsingCubeFact
      assert_equal true, product_hierarchy.isUsingCubeFact
      assert_equal true, time_hierarchy.isUsingCubeFact
    end

    # Java: RolapCubeHierarchyTest#testInit_FactCube_FactTableDiffers
    # Dimensions with an explicit cubeName in a virtual cube get the referenced
    # cube as factCube. When that cube's fact table differs from the dimension's
    # relation table, isUsingCubeFact is false.
    it "returns false when fact cube's fact table differs from hierarchy relation" do
      virtual_cube = lookup_cube("Warehouse and Sales")
      # Customers comes from Sales cube (fact: sales_fact_1997, relation: customer table)
      customers_hierarchy = find_hierarchy(virtual_cube, "Customers")
      # Warehouse comes from Warehouse cube (fact: inventory_fact_1997, relation: warehouse table)
      warehouse_hierarchy = find_hierarchy(virtual_cube, "Warehouse")

      assert_equal false, customers_hierarchy.isUsingCubeFact
      assert_equal false, warehouse_hierarchy.isUsingCubeFact
    end

    # Verify that isUsingCubeFact correctly reflects the relationship between
    # the fact cube's table and the hierarchy's relation for all hierarchies
    # in the virtual cube.
    it "returns expected isUsingCubeFact for all hierarchies in virtual cube" do
      virtual_cube = lookup_cube("Warehouse and Sales")
      results = {}
      virtual_cube.getDimensions.each do |dimension|
        dimension.getHierarchies.each do |hierarchy|
          next unless hierarchy.is_a?(Java::MondrianRolap::RolapCubeHierarchy)
          results[hierarchy.getUniqueName] = hierarchy.isUsingCubeFact
        end
      end

      # Shared dimensions (no cubeName) use virtual cube as factCube with null fact table → true
      assert_equal true, results["[Store]"]
      assert_equal true, results["[Product]"]
      assert_equal true, results["[Time]"]

      # Dimensions with explicit cubeName have a fact cube with a real fact table
      # that differs from the dimension's relation → false
      assert_equal false, results["[Customers]"]
      assert_equal false, results["[Warehouse]"]
      assert_equal false, results["[Gender]"]
    end
  end
end
