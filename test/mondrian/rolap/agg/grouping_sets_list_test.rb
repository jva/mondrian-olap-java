# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2005-2005 Julian Hyde
# Copyright (C) 2005-2018 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/rolap/agg/GroupingSetsListTest.java
describe "GroupingSetsList" do
  BitKey = Java::MondrianRolap::BitKey
  ByteString = Java::MondrianUtil::ByteString

  def get_unsafe
    unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
    unsafe_field.accessible = true
    unsafe_field.get(nil)
  end

  def find_java_class(name)
    class_loader = Java::MondrianRolap::RolapStar.java_class.getClassLoader
    java.lang.Class.forName(name, true, class_loader)
  end

  def set_field(object, field_name, value, declaring_class = nil)
    cls = declaring_class || object.java_class
    cls = cls.java_class if cls.respond_to?(:java_class) && !cls.is_a?(java.lang.Class)
    field = cls.getDeclaredField(field_name)
    field.accessible = true
    field.set(object, value)
  end

  # Create a RolapStar.Table mock via Unsafe allocation with a given alias
  def create_table_mock(table_alias)
    unsafe = get_unsafe
    table_class = find_java_class("mondrian.rolap.RolapStar$Table")
    table = unsafe.allocateInstance(table_class)
    set_field(table, "alias", table_alias, table_class)
    table
  end

  # Create a RolapStar.Column mock via Unsafe allocation with given name and table
  def create_column_mock(column_name, table_alias)
    unsafe = get_unsafe
    column_class = find_java_class("mondrian.rolap.RolapStar$Column")
    column = unsafe.allocateInstance(column_class)
    table = create_table_mock(table_alias)
    set_field(column, "name", column_name, column_class)
    set_field(column, "table", table, column_class)
    column
  end

  # Create a RolapStar.Measure mock via Unsafe allocation
  def create_measure_mock
    unsafe = get_unsafe
    measure_class = find_java_class("mondrian.rolap.RolapStar$Measure")
    column_class = find_java_class("mondrian.rolap.RolapStar$Column")
    measure = unsafe.allocateInstance(measure_class)
    # Set inherited Column fields needed by SegmentBuilder.toHeader
    set_field(measure, "name", "measure_name", column_class)
    table = create_table_mock("MeasureTable")
    set_field(measure, "table", table, column_class)
    # Set Measure-specific field
    set_field(measure, "cubeName", "test_cube", measure_class)
    measure
  end

  # Create a RolapStar mock via Unsafe allocation with schema and fact table
  def create_star_mock
    unsafe = get_unsafe
    star_class = find_java_class("mondrian.rolap.RolapStar")

    # Create RolapSchema mock
    schema_class = find_java_class("mondrian.rolap.RolapSchema")
    schema = unsafe.allocateInstance(schema_class)
    md5 = ByteString.new("test schema".to_java_bytes)
    set_field(schema, "name", "test schema", schema_class)
    set_field(schema, "md5Bytes", md5, schema_class)

    # Create fact table mock
    fact_table = create_table_mock("Table Mock")

    # Create star
    star = unsafe.allocateInstance(star_class)
    set_field(star, "schema", schema, star_class)
    set_field(star, "factTable", fact_table, star_class)
    star
  end

  def create_grouping_set(columns, column_count, star, bit_key, measure)
    selected_columns = columns[0, column_count]
    predicates = [].to_java(Java::MondrianRolap::StarColumnPredicate)
    compound_predicates = java.util.ArrayList.new

    segment_class = find_java_class("mondrian.rolap.agg.Segment")
    constructor = segment_class.getDeclaredConstructors.find { |c| c.getParameterCount == 7 }
    constructor.accessible = true
    segment = constructor.newInstance(
      star, bit_key, selected_columns.to_java(find_java_class("mondrian.rolap.RolapStar$Column")),
      measure, predicates, nil, compound_predicates
    )

    segments = java.util.Arrays.asList(segment)
    grouping_set_class = find_java_class("mondrian.rolap.agg.GroupingSet")
    column_array_class = find_java_class("[Lmondrian.rolap.RolapStar$Column;")
    predicate_array_class = find_java_class("[Lmondrian.rolap.StarColumnPredicate;")
    gs_constructor = grouping_set_class.getDeclaredConstructors.find { |c| c.getParameterCount == 5 }
    gs_constructor.accessible = true
    gs_constructor.newInstance(
      segments, bit_key, bit_key, predicates,
      selected_columns.to_java(find_java_class("mondrian.rolap.RolapStar$Column"))
    )
  end

  def create_grouping_sets_list(grouping_set_list)
    gsl_class = find_java_class("mondrian.rolap.agg.GroupingSetsList")
    constructor = gsl_class.getDeclaredConstructors.first
    constructor.accessible = true
    constructor.newInstance(grouping_set_list)
  end

  # Invoke a no-arg method on a package-private class via reflection
  def invoke_method(object, method_name)
    method = object.getClass.getDeclaredMethod(method_name)
    method.accessible = true
    method.invoke(object)
  end

  # Java: GroupingSetsListTest#testNewGroupingSetsList_RollupColumnsFoundCorrectly
  it "rollup columns found correctly in new GroupingSetsList" do
    bit_key = BitKey::Factory.makeBitKey(0)
    star = create_star_mock
    measure = create_measure_mock

    # Column mocks matching the Java test setup
    col1 = create_column_mock("LV1_ID", "Table1")
    col2 = create_column_mock("LV1_ID", "Table2")
    col3 = create_column_mock("LV1_ID", "Table3")
    col4 = create_column_mock("LV1_ID", "Table4")
    columns = [col1, col2, col3, col4]

    # Create 3 grouping sets: detailed (4 columns), rolled-up (3 columns), rolled-up (2 columns)
    grouping_set_list = java.util.ArrayList.new
    grouping_set_list.add(create_grouping_set(columns, 4, star, bit_key, measure))
    grouping_set_list.add(create_grouping_set(columns, 3, star, bit_key, measure))
    grouping_set_list.add(create_grouping_set(columns, 2, star, bit_key, measure))

    test_object = create_grouping_sets_list(grouping_set_list)

    refute_nil test_object
    assert_same grouping_set_list, invoke_method(test_object, "getGroupingSets")
    assert_equal true, invoke_method(test_object, "useGroupingSets")

    # Verify count of grouping sets for columns
    expected_columns = [
      [col1, col2, col3, col4],
      [col1, col2, col3],
      [col1, col2]
    ]
    grouping_sets_columns = invoke_method(test_object, "getGroupingSetsColumns")
    assert_equal expected_columns.size, grouping_sets_columns.size

    # Verify columns in each of the groups
    expected_columns.each_with_index do |expected_group, i|
      actual_group = grouping_sets_columns.get(i)
      assert_equal expected_group.size, actual_group.length
      expected_group.each_with_index do |expected_col, j|
        assert_equal expected_col, actual_group[j]
      end
    end

    rollup_columns = invoke_method(test_object, "getRollupColumns")
    assert_equal 2, rollup_columns.size
    assert_equal col3, rollup_columns.get(0)
    assert_equal col4, rollup_columns.get(1)
    assert_equal 5, invoke_method(test_object, "getGroupingBitKeyIndex")
  end
end
