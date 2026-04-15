# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2018 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapStarTest.java
describe "RolapStar" do
  # Unsafe allocator for creating Column/Table stubs without invoking constructors.
  unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
  unsafe_field.accessible = true
  UNSAFE_RST = unsafe_field.get(nil)

  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Get the RolapStar for a named cube via the internal Mondrian connection.
  def get_star(cube_name)
    connection = @olap.raw_mondrian_connection
    cube = connection.getSchema.lookupCube(cube_name, true)
    cube.getStar
  end

  # Invoke a protected/package-private method via reflection.
  def invoke_protected_method(object, method_name, param_types_as_classes, *args)
    cls = object.getClass
    method = nil
    while cls
      begin
        method = cls.getDeclaredMethod(method_name, param_types_as_classes.to_java(java.lang.Class))
        break
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end
    raise "Method #{method_name} not found" unless method
    method.setAccessible(true)
    method.invoke(object, *args)
  end

  # Set a private field via reflection.
  def set_field(object, field_name, value)
    cls = object.java_class
    cls = object.getClass if cls.nil?
    field = nil
    klass = object.is_a?(java.lang.Class) ? object : object.getClass
    while klass
      begin
        field = klass.getDeclaredField(field_name)
        break
      rescue java.lang.NoSuchFieldException
        klass = klass.getSuperclass
      end
    end
    raise "Field #{field_name} not found" unless field
    field.setAccessible(true)
    field.set(object, value)
  end

  # Create a Column stub with the given name and table, using Unsafe allocation
  # to bypass the private constructor (replaces Mockito mock).
  def create_column_stub(column_name, table_name)
    column = UNSAFE_RST.allocateInstance(Java::MondrianRolap::RolapStar::Column.java_class)
    table = UNSAFE_RST.allocateInstance(Java::MondrianRolap::RolapStar::Table.java_class)

    set_field(table, "alias", table_name)
    set_field(column, "name", column_name)
    set_field(column, "table", table)

    column
  end

  describe "cloneRelation with filtered table" do
    # Java: RolapStarTest#testCloneRelationWithFilteredTable
    it "respects existing filters when cloning a table" do
      rolap_star = get_star("Sales")

      original = Java::MondrianOlap::MondrianDef::Table.new
      original.name = "TestTable"
      original.alias = "Alias"
      original.schema = "Sechema"
      original.filter = Java::MondrianOlap::MondrianDef::SQL.new
      original.filter.dialect = "generic"
      original.filter.cdata = "Alias.clicked = 'true'"

      # Call protected cloneRelation via reflection
      relation_class = Java::MondrianOlap::MondrianDef::Relation.java_class
      cloned = invoke_protected_method(
        rolap_star, "cloneRelation",
        [relation_class, java.lang.String.java_class],
        original, "NewAlias"
      )

      assert_equal "NewAlias", cloned.alias
      assert_equal "TestTable", cloned.name
      refute_nil cloned.filter
      assert_equal "NewAlias.clicked = 'true'", cloned.filter.cdata
    end
  end

  describe "ColumnComparator" do
    # Java: RolapStarTest#testTwoColumnsWithDifferentNamesNotEquals
    it "columns with different names compare as not equal" do
      comparator = Java::MondrianRolap::RolapStar::ColumnComparator.instance
      column1 = create_column_stub("Column1", "Table1")
      column2 = create_column_stub("Column2", "Table1")
      refute_same column1, column2
      assert_equal(-1, comparator.compare(column1, column2))
    end

    # Java: RolapStarTest#testTwoColumnsWithEqualsNamesButDifferentTablesNotEquals
    it "columns with equal names but different tables compare as not equal" do
      comparator = Java::MondrianRolap::RolapStar::ColumnComparator.instance
      column1 = create_column_stub("Column1", "Table1")
      column2 = create_column_stub("Column1", "Table2")
      refute_same column1, column2
      assert_equal(-1, comparator.compare(column1, column2))
    end

    # Java: RolapStarTest#testTwoColumnsEquals
    it "columns with same name and table compare as equal" do
      comparator = Java::MondrianRolap::RolapStar::ColumnComparator.instance
      column1 = create_column_stub("Column1", "Table1")
      column2 = create_column_stub("Column1", "Table1")
      refute_same column1, column2
      assert_equal 0, comparator.compare(column1, column2)
    end
  end
end
