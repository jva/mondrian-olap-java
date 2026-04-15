# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapDimensionTest.java
describe "RolapDimension" do
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

  # Returns the first hierarchy for a given dimension name in a cube.
  def find_hierarchy(cube, dimension_name)
    dimension = cube.getDimensions.find { |d| d.getName == dimension_name }
    raise "Dimension #{dimension_name} not found in cube #{cube.getName}" unless dimension
    hierarchy = dimension.getHierarchies[0]
    raise "No hierarchy found for #{dimension_name}" unless hierarchy
    hierarchy
  end

  public

  # Java: RolapDimensionTest#testHierarchyRelation
  # Verifies that when a hierarchy has an explicit relation (table),
  # the constructor preserves it on the internal RolapHierarchy relation field
  # rather than overwriting it with cube.getFact().
  it "hierarchy relation is preserved when explicitly set" do
    sales_cube = lookup_cube("Sales")
    cube_hierarchy = find_hierarchy(sales_cube, "Gender")

    # Get the underlying RolapHierarchy (unwrap RolapCubeHierarchy)
    rolap_hierarchy = cube_hierarchy.getRolapHierarchy

    xml_hierarchy = rolap_hierarchy.getXmlHierarchy
    refute_nil xml_hierarchy

    # The XML definition has an explicit <Table> relation
    refute_nil xml_hierarchy.relation,
      "Expected XML hierarchy relation to be set for a dimension with an explicit table"

    # The XML hierarchy relation must NOT be the cube's fact table,
    # which is the actual invariant: the constructor must not overwrite it
    refute_equal sales_cube.getFact, xml_hierarchy.relation,
      "Expected XML hierarchy relation to differ from cube fact table"

    # The internal relation field should reference the same object as the XML
    # relation, proving the constructor preserved it (not overwritten by cube fact)
    assert_equal xml_hierarchy.relation, rolap_hierarchy.getRelation,
      "Expected internal relation to match the explicitly set XML relation"
  end

  # Java: RolapDimensionTest#testHierarchyRelationNotSet
  # Verifies that when a hierarchy has no explicit relation, the constructor
  # assigns cube.getFact() to the internal relation field but does NOT write
  # it back to the XML hierarchy's relation field.
  it "hierarchy without explicit relation keeps XML relation null" do
    store_cube = lookup_cube("Store")
    cube_hierarchy = find_hierarchy(store_cube, "Store Type")

    # Get the underlying RolapHierarchy (unwrap RolapCubeHierarchy)
    rolap_hierarchy = cube_hierarchy.getRolapHierarchy

    xml_hierarchy = rolap_hierarchy.getXmlHierarchy
    refute_nil xml_hierarchy

    # The XML definition has no explicit relation (no <Table> element)
    assert_nil xml_hierarchy.relation,
      "Expected XML hierarchy relation to remain null for a degenerate dimension"

    # The internal relation field should be non-null (assigned cube.getFact()
    # by the constructor), proving the constructor did not write back to XML
    refute_nil rolap_hierarchy.getRelation,
      "Expected internal relation to be set to cube fact table"
  end
end
