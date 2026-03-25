# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/type/TypeTest.java
describe "Type" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  Id = Java::MondrianOlap::Id

  # Finds a cube by name from an array of cubes
  def find_cube(cubes, name)
    cubes.to_a.detect { |c| c.getName == name }
  end

  # Returns a SchemaReader for the Sales cube
  def sales_cube_schema_reader
    connection = @olap.raw_mondrian_connection
    cubes = connection.getSchemaReader.withLocus.getCubes
    sales_cube = find_cube(cubes, "Sales")
    sales_cube.getSchemaReader(connection.getRole).withLocus
  end

  # Looks up a member by name segments
  def lookup_member(schema_reader, *segment_names)
    segments = segment_names.map do |name|
      Id::NameSegment.new(name, Id::Quoting::UNQUOTED)
    end
    schema_reader.getMemberByUniqueName(segments, false)
  end

  # Creates a MemberType from a member
  def member_type_for(member)
    Java::MondrianOlapType::MemberType.new(
      member.getDimension,
      member.getDimension.getHierarchy,
      member.getLevel,
      member
    )
  end

  # Creates a MemberType for a measure member (uses hierarchy's first level)
  def measure_member_type_for(member)
    Java::MondrianOlapType::MemberType.new(
      member.getDimension,
      member.getDimension.getHierarchy,
      member.getDimension.getHierarchy.getLevels[0],
      member
    )
  end

  # Java: TypeTest#testConversions
  it "type conversions are self-consistent and symmetric" do
    connection = @olap.raw_mondrian_connection
    cubes = connection.getSchema.getCubes
    sales_cube = find_cube(cubes, "Sales")
    refute_nil sales_cube

    customers_dimension = sales_cube.getDimensions.to_a.detect { |d| d.getName == "Customers" }
    refute_nil customers_dimension

    hierarchy = customers_dimension.getHierarchy
    member = hierarchy.getDefaultMember
    level = member.getLevel

    member_type = Java::MondrianOlapType::MemberType.new(customers_dimension, hierarchy, level, member)
    level_type = Java::MondrianOlapType::LevelType.new(customers_dimension, hierarchy, level)
    hierarchy_type = Java::MondrianOlapType::HierarchyType.new(customers_dimension, hierarchy)
    dimension_type = Java::MondrianOlapType::DimensionType.new(customers_dimension)
    string_type = Java::MondrianOlapType::StringType.new
    scalar_type = Java::MondrianOlapType::ScalarType.new
    numeric_type = Java::MondrianOlapType::NumericType.new
    date_time_type = Java::MondrianOlapType::DateTimeType.new
    decimal_type = Java::MondrianOlapType::DecimalType.new(10, 2)
    integer_type = Java::MondrianOlapType::DecimalType.new(7, 0)
    null_type = Java::MondrianOlapType::NullType.new
    unknown_member_type = Java::MondrianOlapType::MemberType::Unknown
    tuple_type = Java::MondrianOlapType::TupleType.new(
      [member_type, unknown_member_type].to_java(Java::MondrianOlapType::Type)
    )
    tuple_set_type = Java::MondrianOlapType::SetType.new(tuple_type)
    set_type = Java::MondrianOlapType::SetType.new(member_type)
    unknown_level_type = Java::MondrianOlapType::LevelType::Unknown
    unknown_hierarchy_type = Java::MondrianOlapType::HierarchyType::Unknown
    unknown_dimension_type = Java::MondrianOlapType::DimensionType::Unknown
    boolean_type = Java::MondrianOlapType::BooleanType.new

    types = [
      member_type, level_type, hierarchy_type, dimension_type,
      numeric_type, date_time_type, decimal_type, integer_type,
      scalar_type, null_type, string_type, boolean_type,
      tuple_type, tuple_set_type, set_type,
      unknown_dimension_type, unknown_hierarchy_type,
      unknown_level_type, unknown_member_type
    ]

    # Check that each type is assignable to itself
    types.each do |type|
      desc = "#{type}:#{type.getClass}"
      assert_equal type, type.computeCommonType(type, nil), desc

      conversion_count = [0].to_java(:int)
      assert_equal type, type.computeCommonType(type, conversion_count), desc
      assert_equal 0, conversion_count[0]

      # Check that each scalar type is assignable to nullable with zero conversions
      if type.is_a?(Java::MondrianOlapType::ScalarType)
        assert_equal type, type.computeCommonType(null_type, nil)
        assert_equal type, type.computeCommonType(null_type, conversion_count)
        assert_equal 0, conversion_count[0]
      end
    end

    # Check symmetry and canConvert consistency
    types.each do |from_type|
      types.each do |to_type|
        type = from_type.computeCommonType(to_type, nil)
        type2 = to_type.computeCommonType(from_type, nil)
        desc = "symmetric, from #{from_type}, to #{to_type}"
        if type.nil?
          assert_nil type2, desc
        else
          assert_equal type, type2, desc
        end

        conversion_count = [0].to_java(:int)
        conversion_count2 = [0].to_java(:int)
        type = from_type.computeCommonType(to_type, conversion_count)
        type2 = to_type.computeCommonType(from_type, conversion_count2)
        if conversion_count[0] == 0 && conversion_count2[0] == 0
          if type.nil?
            assert_nil type2, desc
          else
            assert_equal type, type2, desc
          end
        end

        to_category = Java::MondrianOlapType::TypeUtil.typeToCategory(to_type)
        conversions = java.util.ArrayList.new
        can_convert = Java::MondrianOlapType::TypeUtil.canConvert(0, from_type, to_category, conversions)
        if can_convert && conversions.size == 0 && type.nil?
          unless (from_type == member_type && to_type == tuple_type) ||
                 (from_type == tuple_set_type && to_type == set_type) ||
                 (from_type == set_type && to_type == tuple_set_type)
            flunk "can convert from #{from_type} to #{to_type}, but their most general type is null"
          end
        end
        if !can_convert && !type.nil? && type.equals(to_type)
          flunk "cannot convert from #{from_type} to #{to_type}, but they have a most general type #{type}"
        end
      end
    end
  end

  # Java: TypeTest#testCommonTypeWhenSetTypeHavingMemberTypeAndTupleType
  it "common type of SetType with MemberType and SetType with TupleType" do
    reader = sales_cube_schema_reader
    unit_sales = lookup_member(reader, "Measures", "Unit Sales")
    male = lookup_member(reader, "Gender", "M")
    store_ca = lookup_member(reader, "Store", "All Stores", "USA", "CA")

    measure_type = measure_member_type_for(unit_sales)
    gender_type = member_type_for(male)
    store_type = member_type_for(store_ca)

    tuple_type = Java::MondrianOlapType::TupleType.new(
      [store_type, gender_type].to_java(Java::MondrianOlapType::Type)
    )

    set_type_with_member = Java::MondrianOlapType::SetType.new(measure_type)
    set_type_with_tuple = Java::MondrianOlapType::SetType.new(tuple_type)

    type1 = set_type_with_member.computeCommonType(set_type_with_tuple, nil)
    refute_nil type1
    assert_kind_of Java::MondrianOlapType::TupleType, type1.getElementType

    type2 = set_type_with_tuple.computeCommonType(set_type_with_member, nil)
    refute_nil type2
    assert_kind_of Java::MondrianOlapType::TupleType, type2.getElementType
    assert_equal type1, type2
  end

  # Java: TypeTest#testCommonTypeOfMemberandTupleTypeIsTupleType
  it "common type of MemberType and TupleType is TupleType" do
    reader = sales_cube_schema_reader
    unit_sales = lookup_member(reader, "Measures", "Unit Sales")
    male = lookup_member(reader, "Gender", "M")
    store_ca = lookup_member(reader, "Store", "All Stores", "USA", "CA")

    measure_type = measure_member_type_for(unit_sales)
    gender_type = member_type_for(male)
    store_type = member_type_for(store_ca)

    tuple_type = Java::MondrianOlapType::TupleType.new(
      [store_type, gender_type].to_java(Java::MondrianOlapType::Type)
    )

    type1 = measure_type.computeCommonType(tuple_type, nil)
    refute_nil type1
    assert_kind_of Java::MondrianOlapType::TupleType, type1

    type2 = tuple_type.computeCommonType(measure_type, nil)
    refute_nil type2
    assert_kind_of Java::MondrianOlapType::TupleType, type2
    assert_equal type1, type2
  end

  # Java: TypeTest#testCommonTypeBetweenTuplesOfDifferentSizesIsATupleType
  it "common type between tuples of different sizes is a TupleType" do
    reader = sales_cube_schema_reader
    unit_sales = lookup_member(reader, "Measures", "Unit Sales")
    male = lookup_member(reader, "Gender", "M")
    store_ca = lookup_member(reader, "Store", "All Stores", "USA", "CA")

    measure_type = measure_member_type_for(unit_sales)
    gender_type = member_type_for(male)
    store_type = member_type_for(store_ca)

    tuple_type_larger = Java::MondrianOlapType::TupleType.new(
      [store_type, gender_type, measure_type].to_java(Java::MondrianOlapType::Type)
    )
    tuple_type_smaller = Java::MondrianOlapType::TupleType.new(
      [store_type, gender_type].to_java(Java::MondrianOlapType::Type)
    )

    type1 = tuple_type_smaller.computeCommonType(tuple_type_larger, nil)
    refute_nil type1
    assert_kind_of Java::MondrianOlapType::TupleType, type1
    assert_kind_of Java::MondrianOlapType::MemberType, type1.elementTypes[0]
    assert_kind_of Java::MondrianOlapType::MemberType, type1.elementTypes[1]
    assert_kind_of Java::MondrianOlapType::ScalarType, type1.elementTypes[2]

    type2 = tuple_type_larger.computeCommonType(tuple_type_smaller, nil)
    refute_nil type2
    assert_kind_of Java::MondrianOlapType::TupleType, type2
    assert_kind_of Java::MondrianOlapType::MemberType, type2.elementTypes[0]
    assert_kind_of Java::MondrianOlapType::MemberType, type2.elementTypes[1]
    assert_kind_of Java::MondrianOlapType::ScalarType, type2.elementTypes[2]
    assert_equal type1, type2
  end
end
