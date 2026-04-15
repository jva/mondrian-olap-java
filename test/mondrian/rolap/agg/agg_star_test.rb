# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2003-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/rolap/agg/AggStarTest.java
describe "AggStar" do
  BIG_NUMBER = java.lang.Integer::MAX_VALUE + 1

  unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
  unsafe_field.accessible = true
  UNSAFE = unsafe_field.get(nil)

  private

  def find_field(object, field_name)
    cls = object.java_class rescue object.getClass
    while cls
      begin
        field = cls.getDeclaredField(field_name)
        field.accessible = true
        return field
      rescue java.lang.NoSuchFieldException
        cls = cls.getSuperclass
      end
    end
    raise "Field #{field_name} not found"
  end

  def set_java_field(object, field_name, value)
    find_field(object, field_name).set(object, value)
  end

  # Use Unsafe to write primitive fields directly, bypassing final checks and type coercion issues.
  def set_int_field(object, field_name, value)
    field = find_field(object, field_name)
    UNSAFE.putInt(object, UNSAFE.objectFieldOffset(field), value)
  end

  def set_long_field(object, field_name, value)
    field = find_field(object, field_name)
    UNSAFE.putLong(object, UNSAFE.objectFieldOffset(field), value)
  end

  # Creates an AggStar with a FactTable whose numberOfRows and totalColumnSize are set
  # to match the Java test's Mockito-based setup. Uses Unsafe allocation to avoid complex
  # constructor dependencies.
  def create_agg_star
    agg_star = UNSAFE.allocateInstance(Java::MondrianRolapAggmatcher::AggStar.java_class)

    # Create the FactTable inner class. Non-static inner classes have a synthetic "this$0"
    # field referencing the enclosing instance.
    fact_table_class = java.lang.Class.forName(
      "mondrian.rolap.aggmatcher.AggStar$FactTable", true,
      Java::MondrianRolapAggmatcher::AggStar.java_class.getClassLoader
    )
    fact_table = UNSAFE.allocateInstance(fact_table_class)

    # Link the FactTable back to its enclosing AggStar
    set_java_field(fact_table, "this$0", agg_star)

    # Set the fields that getNumberOfRows() and getTotalColumnSize() read.
    # Use Unsafe putInt/putLong to bypass final field restrictions and JRuby type coercion.
    set_long_field(fact_table, "numberOfRows", BIG_NUMBER)
    set_int_field(fact_table, "totalColumnSize", 1)

    # Set the AggStar's aggTable field to point to our FactTable
    set_java_field(agg_star, "aggTable", fact_table)

    agg_star
  end

  # Java: AggStarTest#testSizeIntegerOverflow
  it "returns correct size when row count exceeds Integer.MAX_VALUE" do
    with_properties(ChooseAggregateByVolume: false) do
      agg_star = create_agg_star
      assert_equal BIG_NUMBER, agg_star.getSize
    end
  end

  # Java: AggStarTest#testVolumeIntegerOverflow
  it "returns correct volume when row count exceeds Integer.MAX_VALUE" do
    with_properties(ChooseAggregateByVolume: true) do
      agg_star = create_agg_star
      assert_equal BIG_NUMBER, agg_star.getSize
    end
  end
end
