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

# Java: mondrian/rolap/agg/DenseSegmentBodyTestBase.java
describe "DenseSegmentBody" do
  DenseDoubleSegmentBody = Java::MondrianRolapAgg::DenseDoubleSegmentBody
  DenseIntSegmentBody = Java::MondrianRolapAgg::DenseIntSegmentBody
  Pair = Java::MondrianUtil::Pair

  # Helper to invoke protected/package-private methods via reflection.
  # Walks the superclass chain to find declared methods.
  def invoke_method(object, method_name, *args)
    cls = object.java_class
    method = nil
    if args.empty?
      while cls && method.nil?
        begin
          method = cls.getDeclaredMethod(method_name)
        rescue java.lang.NoSuchMethodException
          cls = cls.getSuperclass
        end
      end
      raise "Method #{method_name} not found" unless method
      method.accessible = true
      method.invoke(object)
    else
      param_types = args.map do |arg|
        case arg
        when Integer
          java.lang.Integer::TYPE
        else
          arg.java_class
        end
      end
      while cls && method.nil?
        begin
          method = cls.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
        rescue java.lang.NoSuchMethodException
          cls = cls.getSuperclass
        end
      end
      raise "Method #{method_name} not found" unless method
      method.accessible = true
      java_args = args.map do |arg|
        case arg
        when Integer
          java.lang.Integer.new(arg)
        else
          arg
        end
      end
      method.invoke(object, *java_args)
    end
  end

  # Instantiate a package-private class via reflection.
  # Uses java_send to call Constructor#newInstance with an explicit Object[] argument,
  # avoiding JRuby's varargs unwrapping that causes coercion failures.
  def new_instance(java_class, param_types, *args)
    constructor = java_class.java_class.getDeclaredConstructor(param_types.to_java(java.lang.Class))
    constructor.accessible = true
    java_args = args.to_java(java.lang.Object)
    constructor.java_send(:newInstance, [Java::JavaLang::Object[].java_class], java_args)
  end

  DOUBLE_ARRAY_CLASS = java.lang.Class.forName("[D")
  INT_ARRAY_CLASS = java.lang.Class.forName("[I")

  # Helper to create a DenseDoubleSegmentBody
  def create_double_body(axes, *values)
    null_values = java.util.BitSet.new
    double_values = Java::double[values.length].new
    values.each_with_index do |v, i|
      if v == 0.0
        null_values.set(i)
        double_values[i] = 0.0
      else
        double_values[i] = v
      end
    end
    new_instance(
      DenseDoubleSegmentBody,
      [java.util.BitSet.java_class, DOUBLE_ARRAY_CLASS, java.util.List.java_class],
      null_values, double_values, axes
    )
  end

  # Helper to create a DenseIntSegmentBody
  def create_int_body(axes, *values)
    null_values = java.util.BitSet.new
    int_values = Java::int[values.length].new
    values.each_with_index do |v, i|
      if v == 0
        null_values.set(i)
        int_values[i] = 0
      else
        int_values[i] = v
      end
    end
    new_instance(
      DenseIntSegmentBody,
      [java.util.BitSet.java_class, INT_ARRAY_CLASS, java.util.List.java_class],
      null_values, int_values, axes
    )
  end

  def empty_axes
    java.util.Collections.emptyList
  end

  def make_axes(*axis_pairs)
    pairs = axis_pairs.map do |values, has_null|
      sorted_set = java.util.TreeSet.new(java.util.Arrays.asList(*values.map { |v| java.lang.Integer.new(v) }))
      Pair.of(sorted_set, java.lang.Boolean.new(has_null))
    end
    java.util.Arrays.asList(*pairs)
  end

  def assert_values_map_correct(body, expected_size)
    value_map = body.getValueMap

    assert_equal expected_size, value_map.size
    assert_equal expected_size, value_map.keySet.size
    assert_equal expected_size, value_map.values.size
    assert_equal expected_size, value_map.entrySet.size

    iterator = value_map.entrySet.iterator
    count = 0
    while count < expected_size
      assert_equal true, iterator.hasNext, count.to_s
      refute_nil iterator.next
      count += 1
    end
    assert_equal false, iterator.hasNext
  end

  describe "DenseDoubleSegmentBody" do
    # Java: DenseSegmentBodyTestBase#testGetObject_NonNull
    it "getObject returns non-null value" do
      body = create_double_body(empty_axes, 1.0)
      result = invoke_method(body, "getObject", 0)
      assert_equal 1.0, result
    end

    # Java: DenseSegmentBodyTestBase#testGetObject_Null
    it "getObject returns null for null value" do
      body = create_double_body(empty_axes, 0.0)
      result = invoke_method(body, "getObject", 0)
      assert_nil result
    end

    # Java: DenseSegmentBodyTestBase#testGetSize_NoNulls
    it "getSize equals getEffectiveSize when no nulls" do
      body = create_double_body(empty_axes, 1.0, 1.0, 1.0)
      size = invoke_method(body, "getSize")
      effective_size = invoke_method(body, "getEffectiveSize")
      assert_equal size, effective_size
    end

    # Java: DenseSegmentBodyTestBase#testGetSize_HasNulls
    it "getSize and getEffectiveSize differ when has nulls" do
      body = create_double_body(empty_axes, 1.0, 0.0, 1.0)
      assert_equal 3, invoke_method(body, "getSize")
      assert_equal 2, invoke_method(body, "getEffectiveSize")
    end

    # Java: DenseSegmentBodyTestBase#testGetSize_OnlyNulls
    it "getEffectiveSize is zero when only nulls" do
      body = create_double_body(empty_axes, 0.0, 0.0, 0.0)
      assert_equal 3, invoke_method(body, "getSize")
      assert_equal 0, invoke_method(body, "getEffectiveSize")
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_NoNullCells_NoNullAxes
    it "getValueMap with no null cells and no null axes" do
      axes = make_axes([[1, 2], false], [[3], false])
      body = create_double_body(axes, 1.0, 1.0, 1.0)
      assert_values_map_correct(body, 3)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_NoNullCells_HasNullAxes
    it "getValueMap with no null cells and has null axes" do
      axes = make_axes([[1, 2], false], [[3], true])
      body = create_double_body(axes, 1.0, 1.0, 1.0, 1.0)
      assert_values_map_correct(body, 4)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_HasNullCells_NoNullAxes
    it "getValueMap with has null cells and no null axes" do
      axes = make_axes([[1, 2], false], [[3], false])
      body = create_double_body(axes, 1.0, 0.0, 1.0, 0.0, 1.0)
      assert_values_map_correct(body, 3)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_HasNullCells_HasNullAxes
    it "getValueMap with has null cells and has null axes" do
      axes = make_axes([[1, 2], false], [[3], true])
      body = create_double_body(axes, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0)
      assert_values_map_correct(body, 4)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_OnlyNullCells_NoNullAxes
    it "getValueMap with only null cells and no null axes" do
      axes = make_axes([[1, 2], false], [[3], false])
      body = create_double_body(axes, 0.0, 0.0)
      assert_values_map_correct(body, 0)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_OnlyNullCells_HasNullAxes
    it "getValueMap with only null cells and has null axes" do
      axes = make_axes([[1, 2], false], [[3], true])
      body = create_double_body(axes, 0.0, 0.0)
      assert_values_map_correct(body, 0)
    end
  end

  describe "DenseIntSegmentBody" do
    # Java: DenseSegmentBodyTestBase#testGetObject_NonNull
    it "getObject returns non-null value" do
      body = create_int_body(empty_axes, 1)
      result = invoke_method(body, "getObject", 0)
      assert_equal 1, result
    end

    # Java: DenseSegmentBodyTestBase#testGetObject_Null
    it "getObject returns null for null value" do
      body = create_int_body(empty_axes, 0)
      result = invoke_method(body, "getObject", 0)
      assert_nil result
    end

    # Java: DenseSegmentBodyTestBase#testGetSize_NoNulls
    it "getSize equals getEffectiveSize when no nulls" do
      body = create_int_body(empty_axes, 1, 1, 1)
      size = invoke_method(body, "getSize")
      effective_size = invoke_method(body, "getEffectiveSize")
      assert_equal size, effective_size
    end

    # Java: DenseSegmentBodyTestBase#testGetSize_HasNulls
    it "getSize and getEffectiveSize differ when has nulls" do
      body = create_int_body(empty_axes, 1, 0, 1)
      assert_equal 3, invoke_method(body, "getSize")
      assert_equal 2, invoke_method(body, "getEffectiveSize")
    end

    # Java: DenseSegmentBodyTestBase#testGetSize_OnlyNulls
    it "getEffectiveSize is zero when only nulls" do
      body = create_int_body(empty_axes, 0, 0, 0)
      assert_equal 3, invoke_method(body, "getSize")
      assert_equal 0, invoke_method(body, "getEffectiveSize")
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_NoNullCells_NoNullAxes
    it "getValueMap with no null cells and no null axes" do
      axes = make_axes([[1, 2], false], [[3], false])
      body = create_int_body(axes, 1, 1, 1)
      assert_values_map_correct(body, 3)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_NoNullCells_HasNullAxes
    it "getValueMap with no null cells and has null axes" do
      axes = make_axes([[1, 2], false], [[3], true])
      body = create_int_body(axes, 1, 1, 1, 1)
      assert_values_map_correct(body, 4)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_HasNullCells_NoNullAxes
    it "getValueMap with has null cells and no null axes" do
      axes = make_axes([[1, 2], false], [[3], false])
      body = create_int_body(axes, 1, 0, 1, 0, 1)
      assert_values_map_correct(body, 3)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_HasNullCells_HasNullAxes
    it "getValueMap with has null cells and has null axes" do
      axes = make_axes([[1, 2], false], [[3], true])
      body = create_int_body(axes, 1, 0, 1, 0, 1, 1)
      assert_values_map_correct(body, 4)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_OnlyNullCells_NoNullAxes
    it "getValueMap with only null cells and no null axes" do
      axes = make_axes([[1, 2], false], [[3], false])
      body = create_int_body(axes, 0, 0)
      assert_values_map_correct(body, 0)
    end

    # Java: DenseSegmentBodyTestBase#testGetValueMap_OnlyNullCells_HasNullAxes
    it "getValueMap with only null cells and has null axes" do
      axes = make_axes([[1, 2], false], [[3], true])
      body = create_int_body(axes, 0, 0)
      assert_values_map_correct(body, 0)
    end
  end
end
