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

require_relative "../../test_helper"

# Java: mondrian/rolap/SqlTupleReaderTest.java
describe "SqlTupleReader" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  private

  def get_unsafe
    unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
    unsafe_field.accessible = true
    unsafe_field.get(nil)
  end

  def find_java_class(name)
    class_loader = @olap.raw_mondrian_connection.getClass.getClassLoader
    java.lang.Class.forName(name, true, class_loader)
  end

  # Set a field on a Java object via reflection, traversing the class hierarchy.
  def set_java_field(object, field_name, value, search_class = nil)
    cls = search_class || object.getClass
    field = nil
    while cls
      begin
        field = cls.getDeclaredField(field_name)
        break
      rescue java.lang.NoSuchFieldException
        cls = cls.getSuperclass
      end
    end
    raise "Field #{field_name} not found" unless field
    field.setAccessible(true)
    field.set(object, value)
  end

  # Create a MondrianDef.Expression proxy that returns a given string
  # for getExpression() and getGenericExpression() calls.
  def create_expression_proxy(expression_string)
    expression_interface = find_java_class("mondrian.olap.MondrianDef$Expression")
    node_def_interface = find_java_class("org.eigenbase.xom.NodeDef")
    handler = ExpressionHandler.new(expression_string)
    java.lang.reflect.Proxy.newProxyInstance(
      expression_interface.getClassLoader,
      [expression_interface, node_def_interface].to_java(java.lang.Class),
      handler
    )
  end

  # Instantiate a private inner class via reflection.
  def create_instance(class_name, constructor_arg_classes, constructor_args)
    cls = find_java_class(class_name)
    constructor = cls.getDeclaredConstructor(constructor_arg_classes.to_java(java.lang.Class))
    constructor.setAccessible(true)
    constructor.newInstance(*constructor_args)
  end

  public

  # Java: SqlTupleReaderTest#testAddLevelMemberSql
  it "addLevelMemberSql calls addToFrom on the aggregate fact table" do
    unsafe = get_unsafe
    connection = @olap.raw_mondrian_connection

    # Create a real SqlQuery with a real dialect
    dialect = Java::MondrianSpi::DialectManager.createDialect(connection.getDataSource, nil)
    sql_query = Java::MondrianRolapSql::SqlQuery.new(dialect)

    # Create stub objects via Unsafe allocation
    level_class = find_java_class("mondrian.rolap.RolapCubeLevel")
    hierarchy_class = find_java_class("mondrian.rolap.RolapCubeHierarchy")
    cube_class = find_java_class("mondrian.rolap.RolapCube")
    star_column_class = find_java_class("mondrian.rolap.RolapStar$Column")
    rolap_star_class = find_java_class("mondrian.rolap.RolapStar")
    property_class = find_java_class("mondrian.rolap.RolapProperty")

    level_iter = unsafe.allocateInstance(level_class)
    target_level = unsafe.allocateInstance(level_class)
    base_cube = unsafe.allocateInstance(cube_class)
    # Set uniqueName on baseCube so equals() comparisons don't NPE
    set_java_field(base_cube, "uniqueName", "[TestCube]",
      find_java_class("mondrian.olap.CubeBase"))
    star_column = unsafe.allocateInstance(star_column_class)
    hierarchy = unsafe.allocateInstance(hierarchy_class)
    rolap_star = unsafe.allocateInstance(rolap_star_class)

    # Create MondrianDef.Expression proxies for the level's key, ordinal, caption, parent expressions
    key_expression = create_expression_proxy("key_col")
    ordinal_expression = create_expression_proxy("ordinal_col")
    property_expression = create_expression_proxy("prop_col")
    agg_key_expression = create_expression_proxy("agg_key_col")
    agg_property_expression = create_expression_proxy("agg_prop_col")
    property_name = "property_1"

    # Set up the RolapProperty via Unsafe
    rolap_property = unsafe.allocateInstance(property_class)
    # Property extends EnumeratedValues.BasicValue which has a "name" field
    set_java_field(rolap_property, "name", property_name,
      find_java_class("mondrian.olap.EnumeratedValues$BasicValue"))
    set_java_field(rolap_property, "exp", property_expression)
    # Set the type field for Property (needed by getType().getInternalType())
    set_java_field(rolap_property, "type", Java::MondrianOlap::Property::Datatype::TYPE_STRING)
    set_java_field(rolap_property, "dependsOnLevelValue", false)

    properties_array = [rolap_property].to_java(find_java_class("mondrian.rolap.RolapProperty"))

    # Set up levelIter (RolapCubeLevel) fields
    set_java_field(level_iter, "keyExp", key_expression)
    set_java_field(level_iter, "ordinalExp", ordinal_expression)
    set_java_field(level_iter, "parentExp", nil)
    set_java_field(level_iter, "captionExp", nil)
    set_java_field(level_iter, "properties", properties_array)
    # Set depth to 0 (default for mock)
    set_java_field(level_iter, "depth", java.lang.Integer.new(0),
      find_java_class("mondrian.olap.LevelBase"))
    # Set flags to 0 (isAll checks FLAG_ALL = 0x02)
    set_java_field(level_iter, "flags", java.lang.Integer.new(0))
    # Set starKeyColumn on levelIter
    set_java_field(level_iter, "starKeyColumn", star_column)
    # Set the hierarchy on levelIter.
    # RolapCubeLevel overrides getHierarchy() to return the cubeHierarchy field,
    # so we must set that rather than the LevelBase.hierarchy field.
    set_java_field(level_iter, "cubeHierarchy", hierarchy)
    set_java_field(level_iter, "hierarchy", hierarchy,
      find_java_class("mondrian.olap.LevelBase"))

    # Set up starColumn
    set_java_field(star_column, "bitPosition", java.lang.Integer.new(0))

    # Set up targetLevel
    set_java_field(target_level, "cubeHierarchy", hierarchy)
    set_java_field(target_level, "hierarchy", hierarchy,
      find_java_class("mondrian.olap.LevelBase"))
    set_java_field(target_level, "depth", java.lang.Integer.new(0),
      find_java_class("mondrian.olap.LevelBase"))

    # Set up a RolapCubeDimension so hierarchy.getCube() returns baseCube.
    # This ensures !cubeHierarchy.getCube().equals(baseCube) is false,
    # so the hierarchy replacement for virtual cubes is skipped.
    cube_dimension_class = find_java_class("mondrian.rolap.RolapCubeDimension")
    cube_dimension = unsafe.allocateInstance(cube_dimension_class)
    set_java_field(cube_dimension, "cube", base_cube)
    set_java_field(hierarchy, "cubeDimension", cube_dimension)

    # Set up hierarchy to return [levelIter] for getLevels()
    # RolapCubeHierarchy overrides getLevels() to return cubeLevels (RolapCubeLevel[])
    cube_levels_array = [level_iter].to_java(find_java_class("mondrian.rolap.RolapCubeLevel"))
    set_java_field(hierarchy, "cubeLevels", cube_levels_array)
    # Also set the HierarchyBase.levels field for any code that accesses it directly
    levels_array = [level_iter].to_java(find_java_class("mondrian.rolap.RolapLevel"))
    set_java_field(hierarchy, "levels", levels_array,
      find_java_class("mondrian.olap.HierarchyBase"))
    # getUniqueKeyLevelName() returns null by default since the field is uninitialized
    # Set relation to a MondrianDef.Table so addToFrom won't throw
    # (needed for the requiresJoinToDim path which calls hierarchy.addToFromInverse)
    relation_table = Java::MondrianOlap::MondrianDef::Table.new
    relation_table.name = "test_dim_table"
    relation_table.alias = "test_dim_table"
    set_java_field(hierarchy, "relation", relation_table)

    # Set up RolapStar with columnCount = 1
    set_java_field(rolap_star, "columnCount", java.lang.Integer.new(1))

    # Create a JdbcSchema.Table mock via Unsafe (needed for AggStar.makeAggStar)
    # Instead, we construct the AggStar directly via its private constructor
    agg_star_class = find_java_class("mondrian.rolap.aggmatcher.AggStar")
    agg_star = unsafe.allocateInstance(agg_star_class)

    # Initialize AggStar fields
    set_java_field(agg_star, "star", rolap_star)
    set_java_field(agg_star, "approxRowCount", java.lang.Long.new(10))

    # Create BitKeys
    bit_key = Java::MondrianRolap::BitKey::Factory.makeBitKey(1)
    set_java_field(agg_star, "bitKey", bit_key)
    set_java_field(agg_star, "levelBitKey", bit_key.emptyCopy)
    set_java_field(agg_star, "measureBitKey", bit_key.emptyCopy)
    set_java_field(agg_star, "foreignKeyBitKey", bit_key.emptyCopy)
    set_java_field(agg_star, "distinctMeasureBitKey", bit_key.emptyCopy)

    # Create the FactTable via reflection (inner class needs enclosing AggStar instance)
    fact_table_class = find_java_class("mondrian.rolap.aggmatcher.AggStar$FactTable")
    # Use the 4-arg constructor: FactTable(String name, MondrianDef.Relation relation, int totalColumnSize, long numberOfRows)
    # But as an inner class of AggStar, the actual constructor signature starts with AggStar
    agg_table_name = "agg_test_table"
    agg_relation = Java::MondrianOlap::MondrianDef::Table.new
    agg_relation.name = agg_table_name
    agg_relation.alias = agg_table_name

    fact_table = create_instance(
      "mondrian.rolap.aggmatcher.AggStar$FactTable",
      [
        agg_star_class,
        java.lang.String.java_class,
        find_java_class("mondrian.olap.MondrianDef$Relation"),
        java.lang.Integer::TYPE,
        java.lang.Long::TYPE
      ],
      [agg_star, agg_table_name, agg_relation, java.lang.Integer.new(100), java.lang.Long.new(10)]
    )

    set_java_field(agg_star, "aggTable", fact_table)

    # Create the columns array on AggStar
    columns_array = java.lang.reflect.Array.newInstance(
      find_java_class("mondrian.rolap.aggmatcher.AggStar$Table$Column"), 1
    )
    set_java_field(agg_star, "columns", columns_array)

    # Initialize levelColumnsToJoin map on AggStar
    set_java_field(agg_star, "levelColumnsToJoin", java.util.HashMap.new)

    # Create the AggStar.Table.Level via reflection
    # Constructor: Level(String name, MondrianDef.Expression expression, int bitPosition,
    #   RolapStar.Column starColumn, boolean collapsed,
    #   MondrianDef.Expression ordinalExp, MondrianDef.Expression captionExp,
    #   Map<String, MondrianDef.Expression> props)
    # As a non-static inner class of Table, the first arg is the enclosing Table instance
    properties_agg = java.util.HashMap.new
    properties_agg.put(property_name, agg_property_expression)

    table_class = find_java_class("mondrian.rolap.aggmatcher.AggStar$Table")
    expression_class = find_java_class("mondrian.olap.MondrianDef$Expression")
    star_column_java_class = find_java_class("mondrian.rolap.RolapStar$Column")

    agg_star_level = create_instance(
      "mondrian.rolap.aggmatcher.AggStar$Table$Level",
      [
        table_class,
        java.lang.String.java_class,
        expression_class,
        java.lang.Integer::TYPE,
        star_column_java_class,
        java.lang.Boolean::TYPE,
        expression_class,
        expression_class,
        java.util.Map.java_class
      ],
      [
        fact_table,
        "level_name",
        agg_key_expression,
        java.lang.Integer.new(0),
        star_column,
        true,  # collapsed
        nil,   # ordinalExp
        nil,   # captionExp
        properties_agg
      ]
    )

    # Now the Level constructor has set bitKey and levelBitKey bits, and added itself to columns[0]
    # Verify columns[0] is now the level
    assert_equal agg_star_level, agg_star.lookupColumn(0)
    assert_equal agg_star_level, agg_star.lookupLevel(0)

    # Create the TupleConstraint proxy (interface)
    tuple_constraint_interface = find_java_class("mondrian.rolap.sql.TupleConstraint")
    sql_constraint_interface = find_java_class("mondrian.rolap.sql.SqlConstraint")
    constraint_handler = NoOpInvocationHandler.new
    constraint_proxy = java.lang.reflect.Proxy.newProxyInstance(
      tuple_constraint_interface.getClassLoader,
      [tuple_constraint_interface, sql_constraint_interface].to_java(java.lang.Class),
      constraint_handler
    )

    # Create SqlTupleReader
    reader = Java::MondrianRolap::SqlTupleReader.new(constraint_proxy)

    # Get WhichSelect.LAST via reflection (package-private enum)
    which_select_class = find_java_class("mondrian.rolap.SqlTupleReader$WhichSelect")
    which_select = which_select_class.getEnumConstants.find { |c| c.name == "LAST" }

    # Call addLevelMemberSql via reflection (it's protected)
    add_level_method = find_java_class("mondrian.rolap.SqlTupleReader").getDeclaredMethod(
      "addLevelMemberSql",
      [
        find_java_class("mondrian.rolap.sql.SqlQuery"),
        find_java_class("mondrian.rolap.RolapLevel"),
        cube_class,
        find_java_class("mondrian.rolap.SqlTupleReader$WhichSelect"),
        agg_star_class
      ].to_java(java.lang.Class)
    )
    add_level_method.setAccessible(true)
    add_level_method.invoke(reader, sql_query, target_level, base_cube, which_select, agg_star)

    # Verify that addToFrom was called on the fact table by checking
    # that the SqlQuery's FROM clause contains the aggregate table name.
    # This is the equivalent of the Java test's:
    #   verify(factTable).addToFrom(any(), eq(false), eq(true))
    sql_output = sql_query.toString
    assert_match(/#{agg_table_name}/, sql_output,
      "Expected SQL output to contain the aggregate table name '#{agg_table_name}', " \
      "confirming addToFrom was called on the fact table")
  end
end

# InvocationHandler for MondrianDef.Expression proxies.
# Returns configured strings for getExpression/getGenericExpression calls.
class ExpressionHandler
  include java.lang.reflect.InvocationHandler

  def initialize(expression_string)
    @expression_string = expression_string
  end

  def invoke(_proxy, method, args)
    case method.getName
    when "getExpression"
      @expression_string
    when "getGenericExpression"
      @expression_string
    when "getTableAlias"
      nil
    when "hashCode"
      java.lang.Integer.new(@expression_string.hash)
    when "equals"
      args && args.to_a[0].equal?(_proxy)
    when "toString"
      @expression_string
    else
      nil
    end
  end
end

# No-op InvocationHandler for TupleConstraint proxy.
class NoOpInvocationHandler
  include java.lang.reflect.InvocationHandler

  def invoke(_proxy, method, _args)
    case method.getName
    when "hashCode"
      java.lang.Integer.new(0)
    when "equals"
      false
    when "toString"
      "NoOpConstraint"
    else
      nil
    end
  end
end
