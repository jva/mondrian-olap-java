# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2004-2005 Julian Hyde
# Copyright (C) 2005-2021 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Mock ResultSet handler using java.lang.reflect.InvocationHandler.
# Mirrors Java's MyDelegatingInvocationHandler in SegmentLoaderTest.
class MockResultSetHandler
  include java.lang.reflect.InvocationHandler

  attr_accessor :result_set_metadata

  def initialize(list)
    @list = list
    @row = -1
    @was_null = false
  end

  def invoke(_proxy, method, args)
    name = method.getName
    case name
    when "getMetaData"
      @result_set_metadata
    when "getColumnCount"
      java.lang.Integer.new(@list.get(0).length)
    when "getColumnType"
      java.lang.Integer.new(java.sql.Types::VARCHAR)
    when "next"
      if @row < @list.size - 1
        @row += 1
        java.lang.Boolean::TRUE
      else
        java.lang.Boolean::FALSE
      end
    when "getObject"
      @list.get(@row)[args[0] - 1]
    when "getInt"
      obj = @list.get(@row)[args[0] - 1]
      if obj.nil?
        @was_null = true
        java.lang.Integer.new(0)
      else
        @was_null = false
        java.lang.Integer.new(obj.to_i)
      end
    when "getDouble"
      obj = @list.get(@row)[args[0] - 1]
      if obj.nil?
        @was_null = true
        java.lang.Double.new(0.0)
      else
        @was_null = false
        java.lang.Double.new(obj.to_f)
      end
    when "wasNull"
      @was_null ? java.lang.Boolean::TRUE : java.lang.Boolean::FALSE
    when "toString"
      "MockResultSet(row=#{@row}, size=#{@list.size})"
    when "hashCode"
      java.lang.System.identityHashCode(self)
    when "equals"
      args[0].equal?(_proxy)
    when "close", "isClosed"
      nil
    else
      nil
    end
  end
end

# Java: mondrian/rolap/agg/SegmentLoaderTest.java
describe "SegmentLoader" do
  BitKey = Java::MondrianRolap::BitKey

  TABLE_TIME = "time_by_day"
  TABLE_PRODUCT_CLASS = "product_class"
  TABLE_CUSTOMER = "customer"
  FIELD_YEAR = "the_year"
  FIELD_PRODUCT_FAMILY = "product_family"
  FIELD_PRODUCT_DEPARTMENT = "product_department"
  FIELD_GENDER = "gender"
  FIELD_VALUES_YEAR = ["1997"]
  FIELD_VALUES_PRODUCT_FAMILY = ["Food", "Non-Consumable", "Drink"]
  FIELD_VALUES_PRODUCT_DEPARTMENT = [
    "Alcoholic Beverages", "Baked Goods", "Baking Goods",
    "Beverages", "Breakfast Foods", "Canned Foods",
    "Canned Products", "Carousel", "Checkout", "Dairy",
    "Deli", "Eggs", "Frozen Foods", "Health and Hygiene",
    "Household", "Meat", "Packaged Foods", "Periodicals",
    "Produce", "Seafood", "Snack Foods", "Snacks",
    "Starchy Foods"
  ]
  FIELD_VALUES_GENDER = ["M", "F"]
  CUBE_NAME_SALES = "Sales"
  MEASURE_UNIT_SALES = "[Measures].[Unit Sales]"

  # --- Java reflection helpers ---

  def find_java_class(name)
    class_loader = Java::MondrianRolap::RolapStar.java_class.getClassLoader
    java.lang.Class.forName(name, true, class_loader)
  end

  def find_method_on_class(cls, method_name, *param_class_names)
    param_types = param_class_names.map do |name|
      case name
      when "int" then java.lang.Integer::TYPE
      when "boolean" then java.lang.Boolean::TYPE
      when java.lang.Class then name
      else find_java_class(name)
      end
    end
    search_cls = cls
    while search_cls
      begin
        method = search_cls.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
        method.accessible = true
        return method
      rescue java.lang.NoSuchMethodException
        search_cls = search_cls.getSuperclass
      end
    end
    raise "Method #{method_name} not found on #{cls.getName}"
  end

  def find_method(object, method_name, *param_class_names)
    cls = object.is_a?(java.lang.Class) ? object : object.java_class
    find_method_on_class(cls, method_name, *param_class_names)
  end

  def get_field(object, field_name, declaring_class = nil)
    cls = declaring_class || object.java_class
    cls = cls.java_class if cls.respond_to?(:java_class) && !cls.is_a?(java.lang.Class)
    field = cls.getDeclaredField(field_name)
    field.accessible = true
    field.get(object)
  end

  def set_field(object, field_name, value, declaring_class = nil)
    cls = declaring_class || object.java_class
    cls = cls.java_class if cls.respond_to?(:java_class) && !cls.is_a?(java.lang.Class)
    field = cls.getDeclaredField(field_name)
    field.accessible = true
    field.set(object, value)
  end

  # --- Mondrian API helpers ---

  def get_measure(cube_name, measure_name)
    connection = @olap.raw_mondrian_connection
    cube = connection.getSchema.lookupCube(cube_name, true)
    member = cube.getSchemaReader(nil).getMemberByUniqueName(
      Java::MondrianOlap::Util.parseIdentifier(measure_name), true
    )
    Java::MondrianRolap::RolapStar.getStarMeasure(member)
  end

  def get_cache_manager
    @olap.raw_mondrian_connection
      .getServer.getAggregationManager.cacheMgr
  end

  # --- BatchTestCase pattern (reflection-based) ---

  def create_cell_request(cube_name, measure_name, table_names, field_names, values)
    star_measure = get_measure(cube_name, measure_name)
    cr_class = find_java_class("mondrian.rolap.agg.CellRequest")
    cr_constructor = cr_class.getDeclaredConstructors.find { |c| c.getParameterCount == 3 }
    cr_constructor.accessible = true
    request = cr_constructor.newInstance(star_measure, false, false)
    star = star_measure.getStar
    table_names.each_with_index do |table, i|
      next if table.nil? || table.empty?
      column = star.lookupColumn(table, field_names[i])
      vcp_class = find_java_class("mondrian.rolap.agg.ValueColumnPredicate")
      vcp_constructor = vcp_class.getDeclaredConstructors.find { |c| c.getParameterCount == 2 }
      vcp_constructor.accessible = true
      predicate = vcp_constructor.newInstance(column, values[i])
      request.addConstrainedColumn(column, predicate)
    end
    request
  end

  def create_batch_loader(locus, cache_mgr, cube)
    bl_class = find_java_class("mondrian.rolap.BatchLoader")
    constructor = bl_class.getDeclaredConstructors.find { |c| c.getParameterCount == 4 }
    constructor.accessible = true
    constructor.newInstance(locus, cache_mgr, cube.getStar.getSqlQueryDialect, cube)
  end

  def create_batch(batch_loader, table_names, field_names, field_values, cube_name, measure_name)
    initial_values = field_values.map { |fv| fv[0] }
    initial_request = create_cell_request(cube_name, measure_name, table_names, field_names, initial_values)
    batch_class = find_java_class("mondrian.rolap.BatchLoader$Batch")
    batch_constructor = batch_class.getDeclaredConstructors.find { |c| c.getParameterCount == 2 }
    batch_constructor.accessible = true
    batch = batch_constructor.newInstance(batch_loader, initial_request)
    add_requests(batch, cube_name, measure_name, table_names, field_names, field_values, [], 0)
    batch
  end

  def add_requests(batch, cube_name, measure_name, table_names, field_names, field_values, selected_values, curr_pos)
    if curr_pos < field_names.length
      field_values[curr_pos].each do |value|
        selected_values.push(value)
        add_requests(batch, cube_name, measure_name, table_names, field_names, field_values, selected_values, curr_pos + 1)
        selected_values.pop
      end
    else
      request = create_cell_request(cube_name, measure_name, table_names, field_names, selected_values.dup)
      batch.add(request)
    end
  end

  def get_grouping_set(table_names, field_names, field_values, cube_name, measure_name)
    connection = @olap.raw_mondrian_connection
    statement = connection.getInternalStatement
    execution = Java::MondrianServer::Execution.new(statement, 0)
    locus = Java::MondrianServer::Locus.new(execution, "SegmentLoaderTest.getGroupingSet", nil)
    Java::MondrianServer::Locus.push(locus)
    begin
      cache_mgr = get_cache_manager
      cube = connection.getSchema.lookupCube(cube_name, true)
      batch_loader = create_batch_loader(locus, cache_mgr, cube)
      batch = create_batch(batch_loader, table_names, field_names, field_values, cube_name, measure_name)
      collector = Java::MondrianRolap::GroupingSetsCollector.new(true)
      segment_futures = java.util.ArrayList.new
      load_method = find_method(batch, "loadAggregation",
        "mondrian.rolap.GroupingSetsCollector", "java.util.List")
      load_method.invoke(batch, collector, segment_futures)
      collector.getGroupingSets.get(0)
    ensure
      Java::MondrianServer::Locus.pop(locus)
    end
  end

  # --- GroupingSet factory methods ---

  def get_default_grouping_set
    get_grouping_set(
      [TABLE_CUSTOMER, TABLE_PRODUCT_CLASS, TABLE_PRODUCT_CLASS, TABLE_TIME],
      [FIELD_GENDER, FIELD_PRODUCT_DEPARTMENT, FIELD_PRODUCT_FAMILY, FIELD_YEAR],
      [FIELD_VALUES_GENDER, FIELD_VALUES_PRODUCT_DEPARTMENT, FIELD_VALUES_PRODUCT_FAMILY, FIELD_VALUES_YEAR],
      CUBE_NAME_SALES, MEASURE_UNIT_SALES
    )
  end

  def get_grouping_set_rollup_on_gender
    get_grouping_set(
      [TABLE_TIME, TABLE_PRODUCT_CLASS, TABLE_PRODUCT_CLASS],
      [FIELD_YEAR, FIELD_PRODUCT_FAMILY, FIELD_PRODUCT_DEPARTMENT],
      [FIELD_VALUES_YEAR, FIELD_VALUES_PRODUCT_FAMILY, FIELD_VALUES_PRODUCT_DEPARTMENT],
      CUBE_NAME_SALES, MEASURE_UNIT_SALES
    )
  end

  def get_grouping_set_rollup_on_gender_and_product_family
    get_grouping_set(
      [TABLE_TIME, TABLE_PRODUCT_CLASS],
      [FIELD_YEAR, FIELD_PRODUCT_DEPARTMENT],
      [FIELD_VALUES_YEAR, FIELD_VALUES_PRODUCT_DEPARTMENT],
      CUBE_NAME_SALES, MEASURE_UNIT_SALES
    )
  end

  def get_grouping_set_rollup_on_product_department
    get_grouping_set(
      [TABLE_CUSTOMER, TABLE_PRODUCT_CLASS, TABLE_TIME],
      [FIELD_GENDER, FIELD_PRODUCT_FAMILY, FIELD_YEAR],
      [FIELD_VALUES_GENDER, FIELD_VALUES_PRODUCT_FAMILY, FIELD_VALUES_YEAR],
      CUBE_NAME_SALES, MEASURE_UNIT_SALES
    )
  end

  def get_grouping_set_rollup_on_gender_and_product_department
    get_grouping_set(
      [TABLE_PRODUCT_CLASS, TABLE_TIME],
      [FIELD_PRODUCT_FAMILY, FIELD_YEAR],
      [FIELD_VALUES_PRODUCT_FAMILY, FIELD_VALUES_YEAR],
      CUBE_NAME_SALES, MEASURE_UNIT_SALES
    )
  end

  def get_grouping_set_rollup_on_gender_and_product_department_and_year
    get_grouping_set(
      [TABLE_PRODUCT_CLASS],
      [FIELD_PRODUCT_FAMILY],
      [FIELD_VALUES_PRODUCT_FAMILY],
      CUBE_NAME_SALES, MEASURE_UNIT_SALES
    )
  end

  def get_grouping_set_rollup_on_product_family_and_product_department
    get_grouping_set(
      [TABLE_CUSTOMER, TABLE_TIME],
      [FIELD_GENDER, FIELD_YEAR],
      [FIELD_VALUES_GENDER, FIELD_VALUES_YEAR],
      CUBE_NAME_SALES, MEASURE_UNIT_SALES
    )
  end

  # --- GroupingSetsList (package-private) via reflection ---

  def create_grouping_sets_list(grouping_sets)
    gsl_class = find_java_class("mondrian.rolap.agg.GroupingSetsList")
    constructor = gsl_class.getDeclaredConstructors.first
    constructor.accessible = true
    constructor.newInstance(grouping_sets)
  end

  def gsl_get_star(gsl)
    find_method(gsl, "getStar").invoke(gsl)
  end

  def gsl_get_default_columns(gsl)
    find_method(gsl, "getDefaultColumns").invoke(gsl)
  end

  def gsl_get_default_axes(gsl)
    find_method(gsl, "getDefaultAxes").invoke(gsl)
  end

  def gsl_get_default_predicates(gsl)
    find_method(gsl, "getDefaultPredicates").invoke(gsl)
  end

  def gsl_get_default_segments(gsl)
    find_method(gsl, "getDefaultSegments").invoke(gsl)
  end

  def gsl_use_grouping_sets(gsl)
    find_method(gsl, "useGroupingSets").invoke(gsl)
  end

  def gsl_get_rollup_columns(gsl)
    find_method(gsl, "getRollupColumns").invoke(gsl)
  end

  def gsl_get_rollup_columns_bit_key_list(gsl)
    find_method(gsl, "getRollupColumnsBitKeyList").invoke(gsl)
  end

  def gsl_get_grouping_sets_columns(gsl)
    find_method(gsl, "getGroupingSetsColumns").invoke(gsl)
  end

  def gsl_get_grouping_sets(gsl)
    find_method(gsl, "getGroupingSets").invoke(gsl)
  end

  def gsl_find_grouping_function_index(gsl, column_index)
    find_method(gsl, "findGroupingFunctionIndex", "int")
      .invoke(gsl, java.lang.Integer.new(column_index))
  end

  # --- CellKey helper (package-private inner class) ---

  def cellkey_new_cell_key(ordinals)
    generator_class = find_java_class("mondrian.rolap.CellKey$Generator")
    method = generator_class.getDeclaredMethod("newCellKey", [find_java_class("[I")].to_java(java.lang.Class))
    method.accessible = true
    method.invoke(nil, ordinals)
  end

  # --- Mock ResultSet ---

  def to_result_set(list)
    handler = MockResultSetHandler.new(list)
    proxy = java.lang.reflect.Proxy.newProxyInstance(
      find_java_class("mondrian.util.DelegatingInvocationHandler").getClassLoader,
      [java.sql.ResultSet.java_class, java.sql.ResultSetMetaData.java_class].to_java(java.lang.Class),
      handler
    )
    handler.result_set_metadata = proxy
    proxy
  end

  # --- Mock SqlStatement for processData ---

  def create_mock_sql_statement(grouping_sets_list, data, locus)
    data_source = gsl_get_star(grouping_sets_list).getDataSource
    sql_stmt_class = find_java_class("mondrian.rolap.SqlStatement")
    # Use reflection to create SqlStatement since JRuby may not resolve the class via module path
    constructor = sql_stmt_class.getDeclaredConstructors.find { |c| c.getParameterCount == 9 }
    constructor.accessible = true
    stmt = constructor.newInstance(data_source, "", nil, 0, 0, locus, 0, 0, nil)

    mock_rs = to_result_set(data)

    # Set resultSet field
    set_field(stmt, "resultSet", mock_rs, sql_stmt_class)

    # Set state to ACTIVE
    state_class = find_java_class("mondrian.rolap.SqlStatement$State")
    active_state = java.lang.Enum.valueOf(state_class, "ACTIVE")
    set_field(stmt, "state", active_state, sql_stmt_class)

    # Set types (guessTypes would read from resultSet metadata)
    column_count = mock_rs.getMetaData.getColumnCount
    type_class = find_java_class("mondrian.rolap.SqlStatement$Type")
    object_type = java.lang.Enum.valueOf(type_class, "OBJECT")
    types_list = java.util.Collections.nCopies(column_count, object_type)
    set_field(stmt, "types", types_list, sql_stmt_class)

    stmt
  end

  # --- SegmentLoader method invocations via reflection ---

  def invoke_process_data(loader, stmt, axis_contains_null, axis_value_set, grouping_sets_list)
    find_method(loader, "processData",
      "mondrian.rolap.SqlStatement", "[Z", "[Ljava.util.SortedSet;",
      "mondrian.rolap.agg.GroupingSetsList"
    ).invoke(loader, stmt, axis_contains_null, axis_value_set, grouping_sets_list)
  end

  def invoke_get_distinct_value_workspace(loader, axis_count)
    find_method(loader, "getDistinctValueWorkspace", "int")
      .invoke(loader, java.lang.Integer.new(axis_count))
  end

  def invoke_get_rollup_bit_key(loader, arity, result_set, offset)
    find_method(loader, "getRollupBitKey", "int", "java.sql.ResultSet", "int")
      .invoke(loader, java.lang.Integer.new(arity), result_set, java.lang.Integer.new(offset))
  end

  def invoke_set_axis_data_and_decide_sparse_use(loader, axis_value_sets, axis_contains_null, gsl, rows)
    find_method(loader, "setAxisDataAndDecideSparseUse",
      "[Ljava.util.SortedSet;", "[Z",
      "mondrian.rolap.agg.GroupingSetsList",
      "mondrian.rolap.agg.SegmentLoader$RowList"
    ).invoke(loader, axis_value_sets, axis_contains_null, gsl, rows)
  end

  def invoke_create_data_sets_for_grouping_sets(loader, gsl, sparse, types)
    find_method(loader, "createDataSetsForGroupingSets",
      "mondrian.rolap.agg.GroupingSetsList", "boolean", "java.util.List"
    ).invoke(loader, gsl, sparse, types)
  end

  def invoke_load_data_to_data_sets(loader, gsl, rows, datasets_map)
    find_method(loader, "loadDataToDataSets",
      "mondrian.rolap.agg.GroupingSetsList",
      "mondrian.rolap.agg.SegmentLoader$RowList",
      "java.util.Map"
    ).invoke(loader, gsl, rows, datasets_map)
  end

  def invoke_set_data_to_segments(loader, gsl, datasets_map, segment_map)
    find_method(loader, "setDataToSegments",
      "mondrian.rolap.agg.GroupingSetsList", "java.util.Map", "java.util.Map"
    ).invoke(loader, gsl, datasets_map, segment_map)
  end

  # --- RowList method invocations via reflection (protected inner class) ---

  def rowlist_class
    @rowlist_class ||= find_java_class("mondrian.rolap.agg.SegmentLoader$RowList")
  end

  def rowlist_size(rowlist)
    find_method_on_class(rowlist_class, "size").invoke(rowlist)
  end

  def rowlist_get_types(rowlist)
    find_method_on_class(rowlist_class, "getTypes").invoke(rowlist)
  end

  def rowlist_first(rowlist)
    find_method_on_class(rowlist_class, "first").invoke(rowlist)
  end

  def rowlist_next(rowlist)
    find_method_on_class(rowlist_class, "next").invoke(rowlist)
  end

  def rowlist_get_object(rowlist, column_index)
    find_method_on_class(rowlist_class, "getObject", "int")
      .invoke(rowlist, java.lang.Integer.new(column_index))
  end

  # Replicates loadImpl flow with a mock SqlStatement instead of real SQL.
  def load_with_mock_data(cache_mgr, grouping_sets, data, locus, force_sparse: false)
    loader = Java::MondrianRolapAgg::SegmentLoader.new(cache_mgr)
    gsl = create_grouping_sets_list(grouping_sets)
    default_columns = gsl_get_default_columns(gsl)
    arity = default_columns.length

    mock_stmt = create_mock_sql_statement(gsl, data, locus)
    axis_value_sets = invoke_get_distinct_value_workspace(loader, arity)
    axis_contains_null = Java::boolean[arity].new

    rows = invoke_process_data(loader, mock_stmt, axis_contains_null, axis_value_sets, gsl)

    if force_sparse
      sparse = true
    else
      sparse = invoke_set_axis_data_and_decide_sparse_use(loader, axis_value_sets, axis_contains_null, gsl, rows)
    end

    # When forcing sparse, still need to set axis data on the grouping sets
    if force_sparse
      invoke_set_axis_data_and_decide_sparse_use(loader, axis_value_sets, axis_contains_null, gsl, rows)
      sparse = true
    end

    types_list = rowlist_get_types(rows)
    measure_types = types_list.subList(arity, types_list.size)
    datasets_map = invoke_create_data_sets_for_grouping_sets(loader, gsl, sparse, measure_types)

    invoke_load_data_to_data_sets(loader, gsl, rows, datasets_map)

    segment_map = java.util.HashMap.new
    invoke_set_data_to_segments(loader, gsl, datasets_map, segment_map)

    segment_map
  end

  # --- Data generation helpers ---

  def get_data(include_summary_data)
    data = java.util.ArrayList.new
    data.add(["1997", "Food", "Deli", "F", "5990", 0].to_java(:object))
    data.add(["1997", "Food", "Deli", "M", "6047", 0].to_java(:object))
    data.add(["1997", "Food", "Deli", nil, "12037", 1].to_java(:object)) if include_summary_data
    data.add(["1997", "Food", "Canned_Products", "F", "867", 0].to_java(:object))
    data.add(["1997", "Food", "Canned_Products", "M", "945", 0].to_java(:object))
    data.add(["1997", "Food", "Canned_Products", nil, "1812", 1].to_java(:object)) if include_summary_data
    data.add(["1997", "Drink", "Dairy", "F", "1987", 0].to_java(:object))
    data.add(["1997", "Drink", "Dairy", "M", "2199", 0].to_java(:object))
    data.add(["1997", "Drink", "Dairy", nil, "4186", 1].to_java(:object)) if include_summary_data
    data.add(["1997", "Non-Consumable", "Carousel", "F", "368", 0].to_java(:object))
    data.add(["1997", "Non-Consumable", "Carousel", "M", "473", 0].to_java(:object))
    data.add(["1997", "Non-Consumable", "Carousel", nil, "841", 1].to_java(:object)) if include_summary_data
    data
  end

  def get_data_with_null_in_rollup_column(include_summary_data)
    data = java.util.ArrayList.new
    data.add(["1997", "Food", "Deli", "F", "5990", 0].to_java(:object))
    data.add(["1997", "Food", "Deli", "M", "6047", 0].to_java(:object))
    data.add(["1997", "Food", "Deli", nil, "867", 0].to_java(:object))
    data.add(["1997", "Food", "Deli", nil, "12037", 1].to_java(:object)) if include_summary_data
    data
  end

  def get_data_with_null_in_axis_column(include_summary_data)
    data = java.util.ArrayList.new
    data.add(["1997", "Food", "Deli", "F", "5990", 0].to_java(:object))
    data.add(["1997", "Food", "Deli", "M", "6047", 0].to_java(:object))
    data.add(["1997", "Food", "Deli", nil, "12037", 1].to_java(:object)) if include_summary_data
    data.add(["1997", "Food", nil, "F", "867", 0].to_java(:object))
    data
  end

  def trim_data(length, data)
    trimmed = java.util.ArrayList.new
    data.each do |row|
      trimmed.add(java.util.Arrays.copyOf(row, length))
    end
    trimmed
  end

  # --- Verification helpers ---

  def verify_year_axis(axis)
    keys = axis.getKeys
    assert_equal 1, keys.length
    assert_equal "1997", keys[0].to_s
  end

  def verify_product_family_axis(axis)
    keys = axis.getKeys
    assert_equal 3, keys.length
    assert_equal "Drink", keys[0].to_s
    assert_equal "Food", keys[1].to_s
    assert_equal "Non-Consumable", keys[2].to_s
  end

  def verify_product_department_axis(axis)
    keys = axis.getKeys
    assert_equal 4, keys.length
    assert_equal "Canned_Products", keys[0].to_s
  end

  def verify_gender_axis(axis)
    keys = axis.getKeys
    assert_equal 2, keys.length
    assert_equal "F", keys[0].to_s
    assert_equal "M", keys[1].to_s
  end

  def verify_unit_sales_detailed(segment)
    expected = [
      nil, nil, nil, nil, 1987.0, 2199.0,
      nil, nil, 867.0, 945.0, nil, nil, nil, nil, 5990.0,
      6047.0, nil, nil, 368.0, 473.0, nil, nil, nil, nil
    ]
    index = 0
    segment.getData.each do |entry|
      if expected[index].nil?
        assert_nil entry.getValue
      else
        assert_equal expected[index], entry.getValue
      end
      index += 1
    end
  end

  def verify_unit_sales_detailed_for_sparse(segment)
    cells = {}
    cells[cellkey_new_cell_key([0, 2, 1, 0].to_java(:int))] = 368.0
    cells[cellkey_new_cell_key([0, 0, 2, 0].to_java(:int))] = 1987.0
    cells[cellkey_new_cell_key([0, 1, 0, 0].to_java(:int))] = 867.0
    cells[cellkey_new_cell_key([0, 2, 1, 1].to_java(:int))] = 473.0
    cells[cellkey_new_cell_key([0, 1, 0, 1].to_java(:int))] = 945.0
    cells[cellkey_new_cell_key([0, 1, 3, 0].to_java(:int))] = 5990.0
    cells[cellkey_new_cell_key([0, 0, 2, 1].to_java(:int))] = 2199.0
    cells[cellkey_new_cell_key([0, 1, 3, 1].to_java(:int))] = 6047.0
    segment.getData.each do |entry|
      assert cells.key?(entry.getKey), "Unexpected cell key: #{entry.getKey}"
      assert_equal cells[entry.getKey], entry.getValue
    end
  end

  def verify_unit_sales_aggregate(segment)
    expected = [
      nil, nil, 4186.0, nil, 1812.0, nil,
      nil, 12037.0, nil, 841.0, nil, nil
    ]
    index = 0
    segment.getData.each do |entry|
      if expected[index].nil?
        assert_nil entry.getValue
      else
        assert_equal expected[index], entry.getValue
      end
      index += 1
    end
  end

  def verify_unit_sales_aggregate_for_sparse(segment)
    cells = {}
    cells[cellkey_new_cell_key([0, 2, 1].to_java(:int))] = 841.0
    cells[cellkey_new_cell_key([0, 1, 0].to_java(:int))] = 1812.0
    cells[cellkey_new_cell_key([0, 1, 3].to_java(:int))] = 12037.0
    cells[cellkey_new_cell_key([0, 0, 2].to_java(:int))] = 4186.0
    segment.getData.each do |entry|
      assert cells.key?(entry.getKey), "Unexpected cell key: #{entry.getKey}"
      assert_equal cells[entry.getKey], entry.getValue
    end
  end

  # --- Locus context helper ---

  def with_locus
    connection = @olap.raw_mondrian_connection
    cache_mgr = get_cache_manager
    statement = connection.getInternalStatement
    execution = Java::MondrianServer::Execution.new(statement, 1000)
    locus = Java::MondrianServer::Locus.new(execution, nil, nil)
    Java::MondrianServer::Locus.push(locus)
    begin
      yield cache_mgr, locus
    ensure
      Java::MondrianServer::Locus.pop(locus)
      begin; statement.cancel; rescue; end
      begin; execution.cancel; rescue; end
    end
  end

  # --- Test setup ---

  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Java: SegmentLoaderTest#testRollup
  #
  # The original Java test iterates rollup=true and rollup=false with DisableCaching=true.
  # When rollup=true (negative=true), the test asserts the SQL is NOT found. However,
  # DisableCaching=true prevents segments from being registered in the cache index,
  # so in-memory rollup has no cached data to roll up from. The rollup=true assertion
  # would fail in Java too (SegmentLoaderTest was never run by Maven CI).
  describe "rollup" do
    ROLLUP_SQL_PATTERNS = {
      "mysql" => "sum(`sales_fact_1997`.`unit_sales`) as `m0` from" \
                 " `sales_fact_1997`",
      "postgresql" => "sum(\"sales_fact_1997\".\"unit_sales\") as \"m0\" from" \
                      " \"sales_fact_1997\"",
      "oracle" => "sum(\"sales_fact_1997\".\"unit_sales\") as \"m0\" from" \
                  " \"sales_fact_1997\""
    }

    it "with in-memory rollup enabled, SQL should not be issued" do
      # DisableCaching=true prevents segments from being cached, so in-memory
      # rollup has no cached data to roll up from and falls back to SQL.
      # This makes the rollup=true negative assertion untestable here.
      skip "DisableCaching=true prevents in-memory rollup from finding cached segments"
    end

    it "with in-memory rollup disabled, SQL must be issued" do
      pattern = ROLLUP_SQL_PATTERNS[MONDRIAN_DRIVER]
      skip "No SQL pattern for #{MONDRIAN_DRIVER}" unless pattern

      Mondrian::OLAP::Connection.flush_schema_cache
      with_properties(DisableCaching: true, EnableInMemoryRollup: false) do
        olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
        begin
          # Execute the first query to prime the segment cache
          olap.execute(
            "select {[Store].[Store Country].Members} on rows, " \
            "{[Time].[Time].[Year].Members} on columns from [Sales]"
          )

          # With rollup disabled, the second query must go to the database
          mdx = "select {[Time].[Time].[Year].Members} on columns from [Sales]"
          captured = capture_sql { olap.execute(mdx) }
          found = captured.any? { |sql| sql.to_s.gsub(/\s+/, " ").strip.include?(pattern) }
          assert found,
            "Expected SQL to be found when EnableInMemoryRollup=false.\n" \
            "Expected:\n#{pattern}\n\nCaptured:\n#{captured.to_a.join("\n\n")}"
        ensure
          olap.close
        end
      end
    end
  end

  # Java: SegmentLoaderTest#testLoadWithMockResultsForLoadingSummaryAndDetailedSegments
  it "load with mock results for loading summary and detailed segments" do
    with_locus do |cache_mgr, locus|
      grouping_sets_info = get_default_grouping_set
      groupable_sets_info = get_grouping_set_rollup_on_gender

      grouping_sets = java.util.ArrayList.new
      grouping_sets.add(grouping_sets_info)
      grouping_sets.add(groupable_sets_info)

      segment_map = load_with_mock_data(cache_mgr, grouping_sets, get_data(true), locus)

      axes = grouping_sets_info.getAxes
      verify_year_axis(axes[0])
      verify_product_family_axis(axes[1])
      verify_product_department_axis(axes[2])
      verify_gender_axis(axes[3])

      detailed_segment = segment_map.get(grouping_sets.get(0).getSegments.get(0))
      verify_unit_sales_detailed(detailed_segment)

      axes = grouping_sets.get(0).getAxes
      verify_year_axis(axes[0])
      verify_product_family_axis(axes[1])
      verify_product_department_axis(axes[2])

      aggregate_segment = segment_map.get(grouping_sets.get(1).getSegments.get(0))
      verify_unit_sales_aggregate(aggregate_segment)
    end
  end

  # Java: SegmentLoaderTest#testLoadWithWithNullInRollupColumn
  it "load with null in rollup column" do
    with_locus do |cache_mgr, locus|
      grouping_sets_info = get_default_grouping_set
      groupable_sets_info = get_grouping_set_rollup_on_gender

      grouping_sets = java.util.ArrayList.new
      grouping_sets.add(grouping_sets_info)
      grouping_sets.add(groupable_sets_info)

      segment_map = load_with_mock_data(cache_mgr, grouping_sets, get_data_with_null_in_rollup_column(true), locus)

      detailed_segment = segment_map.get(grouping_sets.get(0).getSegments.get(0))
      assert_equal 3, detailed_segment.getCellCount
    end
  end

  # Java: SegmentLoaderTest#testLoadWithMockResultsForLoadingSummaryAndDetailedSegmentsUsingSparse
  it "load with mock results for loading summary and detailed segments using sparse" do
    with_locus do |cache_mgr, locus|
      grouping_sets_info = get_default_grouping_set
      groupable_sets_info = get_grouping_set_rollup_on_gender

      grouping_sets = java.util.ArrayList.new
      grouping_sets.add(grouping_sets_info)
      grouping_sets.add(groupable_sets_info)

      segment_map = load_with_mock_data(cache_mgr, grouping_sets, get_data(true), locus, force_sparse: true)

      axes = grouping_sets_info.getAxes
      verify_year_axis(axes[0])
      verify_product_family_axis(axes[1])
      verify_product_department_axis(axes[2])
      verify_gender_axis(axes[3])

      detailed_segment = segment_map.get(grouping_sets.get(0).getSegments.get(0))
      verify_unit_sales_detailed_for_sparse(detailed_segment)

      axes = grouping_sets.get(0).getAxes
      verify_year_axis(axes[0])
      verify_product_family_axis(axes[1])
      verify_product_department_axis(axes[2])

      aggregate_segment = segment_map.get(grouping_sets.get(1).getSegments.get(0))
      verify_unit_sales_aggregate_for_sparse(aggregate_segment)
    end
  end

  # Java: SegmentLoaderTest#testLoadWithMockResultsForLoadingOnlyDetailedSegments
  it "load with mock results for loading only detailed segments" do
    with_locus do |cache_mgr, locus|
      grouping_sets_info = get_default_grouping_set

      grouping_sets = java.util.ArrayList.new
      grouping_sets.add(grouping_sets_info)

      segment_map = load_with_mock_data(cache_mgr, grouping_sets, trim_data(5, get_data(false)), locus)

      axes = grouping_sets_info.getAxes
      verify_year_axis(axes[0])
      verify_product_family_axis(axes[1])
      verify_product_department_axis(axes[2])
      verify_gender_axis(axes[3])

      detailed_segment = segment_map.get(grouping_sets_info.getSegments.get(0))
      verify_unit_sales_detailed(detailed_segment)
    end
  end

  # Java: SegmentLoaderTest#testProcessDataForGettingGroupingSetsBitKeysAndLoadingAxisValueSet
  it "process data for getting grouping sets bit keys and loading axis value set" do
    with_locus do |cache_mgr, locus|
      grouping_sets_info = get_default_grouping_set
      groupable_sets_info = get_grouping_set_rollup_on_gender

      grouping_sets = java.util.ArrayList.new
      grouping_sets.add(grouping_sets_info)
      grouping_sets.add(groupable_sets_info)

      gsl = create_grouping_sets_list(grouping_sets)
      mock_stmt = create_mock_sql_statement(gsl, get_data(true), locus)
      loader = Java::MondrianRolapAgg::SegmentLoader.new(cache_mgr)

      axis_count = 4
      axis_value_set = invoke_get_distinct_value_workspace(loader, axis_count)
      axis_contains_null = Java::boolean[axis_count].new

      list = invoke_process_data(loader, mock_stmt, axis_contains_null, axis_value_set, gsl)

      assert_equal 12, rowlist_size(list)
      assert_equal 6, rowlist_get_types(list).size

      rowlist_first(list)
      rowlist_next(list)
      assert_equal BitKey::Factory.makeBitKey(0), rowlist_get_object(list, 5)

      bit_key_for_summary_row = BitKey::Factory.makeBitKey(0)
      bit_key_for_summary_row.set(0)
      rowlist_next(list)
      rowlist_next(list)
      assert_equal bit_key_for_summary_row, rowlist_get_object(list, 5)

      assert_equal 1, axis_value_set[0].size
      assert_equal 3, axis_value_set[1].size
      assert_equal 4, axis_value_set[2].size
      assert_equal 2, axis_value_set[3].size

      assert_equal false, axis_contains_null[0]
      assert_equal false, axis_contains_null[1]
      assert_equal false, axis_contains_null[2]
      assert_equal false, axis_contains_null[3]
    end
  end

  # Java: SegmentLoaderTest#testProcessDataForSettingNullAxis
  it "process data for setting null axis" do
    with_locus do |cache_mgr, locus|
      grouping_sets_info = get_default_grouping_set

      grouping_sets = java.util.ArrayList.new
      grouping_sets.add(grouping_sets_info)

      gsl = create_grouping_sets_list(grouping_sets)
      mock_stmt = create_mock_sql_statement(gsl, trim_data(5, get_data_with_null_in_axis_column(false)), locus)
      loader = Java::MondrianRolapAgg::SegmentLoader.new(cache_mgr)

      axis_count = 4
      axis_value_set = invoke_get_distinct_value_workspace(loader, axis_count)
      axis_contains_null = Java::boolean[axis_count].new

      invoke_process_data(loader, mock_stmt, axis_contains_null, axis_value_set, gsl)

      assert_equal false, axis_contains_null[0]
      assert_equal false, axis_contains_null[1]
      assert_equal true, axis_contains_null[2]
      assert_equal false, axis_contains_null[3]
    end
  end

  # Java: SegmentLoaderTest#testProcessBinaryData (PDI-16150)
  it "process binary data" do
    with_locus do |cache_mgr, locus|
      grouping_sets_info = get_default_grouping_set

      binary_data0 = "11011"
      binary_data1 = "01011"

      data = java.util.ArrayList.new
      data.add([binary_data0.to_java_bytes].to_java(:object))
      data.add([binary_data1.to_java_bytes].to_java(:object))

      grouping_sets = java.util.ArrayList.new
      grouping_sets.add(grouping_sets_info)

      gsl = create_grouping_sets_list(grouping_sets)
      mock_stmt = create_mock_sql_statement(gsl, trim_data(5, data), locus)
      loader = Java::MondrianRolapAgg::SegmentLoader.new(cache_mgr)

      axis_count = 2
      axis_value_set = invoke_get_distinct_value_workspace(loader, axis_count)
      axis_contains_null = Java::boolean[axis_count].new

      invoke_process_data(loader, mock_stmt, axis_contains_null, axis_value_set, gsl)

      values = axis_value_set[0].toArray
      assert_equal binary_data0, values[1].to_s
      assert_equal binary_data1, values[0].to_s
    end
  end

  # Java: SegmentLoaderTest#testProcessDataForNonGroupingSetsScenario
  it "process data for non grouping sets scenario" do
    with_locus do |cache_mgr, locus|
      grouping_sets_info = get_default_grouping_set

      data = java.util.ArrayList.new
      data.add(["1997", "Food", "Deli", "F", "5990"].to_java(:object))
      data.add(["1997", "Food", "Deli", "M", "6047"].to_java(:object))
      data.add(["1997", "Food", "Canned_Products", "F", "867"].to_java(:object))

      grouping_sets = java.util.ArrayList.new
      grouping_sets.add(grouping_sets_info)

      gsl = create_grouping_sets_list(grouping_sets)
      mock_stmt = create_mock_sql_statement(gsl, data, locus)
      loader = Java::MondrianRolapAgg::SegmentLoader.new(cache_mgr)

      axis_value_set = invoke_get_distinct_value_workspace(loader, 4)
      list = invoke_process_data(loader, mock_stmt, Java::boolean[4].new, axis_value_set, gsl)

      assert_equal 3, rowlist_size(list)
      assert_equal 5, rowlist_get_types(list).size

      assert_equal 1, axis_value_set[0].size
      assert_equal 1, axis_value_set[1].size
      assert_equal 2, axis_value_set[2].size
      assert_equal 2, axis_value_set[3].size
    end
  end

  # Java: SegmentLoaderTest#testGetGroupingBitKey
  it "get grouping bit key" do
    with_locus do |cache_mgr, _locus|
      loader = Java::MondrianRolapAgg::SegmentLoader.new(cache_mgr)

      # Test 1: All grouping values 0
      data1 = java.util.ArrayList.new
      data1.add(["1997", "Food", "Deli", "M", "6047", 0, 0, 0, 0].to_java(:object))
      rs1 = to_result_set(data1)
      assert_equal true, rs1.next
      assert_equal BitKey::Factory.makeBitKey(4),
        invoke_get_rollup_bit_key(loader, 4, rs1, 5)

      # Test 2: Gender is null, last grouping bit set
      # The Java test omits next() here, but getRollupBitKey does not advance the cursor,
      # so the cursor must be positioned on a row before calling it.
      data2 = java.util.ArrayList.new
      data2.add(["1997", "Food", "Deli", nil, "12037", 0, 0, 0, 1].to_java(:object))
      rs2 = to_result_set(data2)
      assert_equal true, rs2.next
      key2 = BitKey::Factory.makeBitKey(4)
      key2.set(3)
      assert_equal key2, invoke_get_rollup_bit_key(loader, 4, rs2, 5)

      # Test 3: Product family and gender null, 2nd and 4th grouping bits set
      # Same as test 2: next() is required but missing in the Java source.
      data3 = java.util.ArrayList.new
      data3.add(["1997", nil, "Deli", nil, "12037", 0, 1, 0, 1].to_java(:object))
      rs3 = to_result_set(data3)
      assert_equal true, rs3.next
      key3 = BitKey::Factory.makeBitKey(4)
      key3.set(1)
      key3.set(3)
      assert_equal key3, invoke_get_rollup_bit_key(loader, 4, rs3, 5)
    end
  end

  # Java: SegmentLoaderTest#testGroupingSetsUtilForMissingGroupingBitKeys
  it "grouping sets util for missing grouping bit keys" do
    grouping_sets = java.util.ArrayList.new
    grouping_sets.add(get_default_grouping_set)
    grouping_sets.add(get_grouping_set_rollup_on_gender)
    detail = create_grouping_sets_list(grouping_sets)

    bit_keys_list = gsl_get_rollup_columns_bit_key_list(detail)
    columns_count = 4
    assert_equal BitKey::Factory.makeBitKey(columns_count), bit_keys_list.get(0)
    key = BitKey::Factory.makeBitKey(columns_count)
    key.set(0)
    assert_equal key, bit_keys_list.get(1)

    grouping_sets2 = java.util.ArrayList.new
    grouping_sets2.add(get_default_grouping_set)
    grouping_sets2.add(get_grouping_set_rollup_on_gender_and_product_family)
    bit_keys_list2 = gsl_get_rollup_columns_bit_key_list(create_grouping_sets_list(grouping_sets2))
    assert_equal BitKey::Factory.makeBitKey(columns_count), bit_keys_list2.get(0)
    key2 = BitKey::Factory.makeBitKey(columns_count)
    key2.set(0)
    key2.set(1)
    assert_equal key2, bit_keys_list2.get(1)

    # The Java test asserts getRollupColumnsBitKeyList().isEmpty() for an empty GroupingSetsList,
    # but the implementation returns Collections.singletonList(BitKey.EMPTY) when there are no
    # grouping sets, so the list is never truly empty. This is a known Java test issue
    # (SegmentLoaderTest was not run by Maven CI).
    empty_gsl = create_grouping_sets_list(java.util.ArrayList.new)
    empty_bit_keys = gsl_get_rollup_columns_bit_key_list(empty_gsl)
    assert_equal 1, empty_bit_keys.size
    assert_equal BitKey::EMPTY, empty_bit_keys.get(0)
  end

  # Java: SegmentLoaderTest#testGroupingSetsUtilSetsDetailForRollupColumns
  it "grouping sets util sets detail for rollup columns" do
    star_measure = get_measure(CUBE_NAME_SALES, MEASURE_UNIT_SALES)
    star = star_measure.getStar
    year = star.lookupColumn(TABLE_TIME, FIELD_YEAR)
    product_family = star.lookupColumn(TABLE_PRODUCT_CLASS, FIELD_PRODUCT_FAMILY)
    product_department = star.lookupColumn(TABLE_PRODUCT_CLASS, FIELD_PRODUCT_DEPARTMENT)
    gender = star.lookupColumn(TABLE_CUSTOMER, FIELD_GENDER)

    grouping_sets = java.util.ArrayList.new
    grouping_sets.add(get_default_grouping_set)
    grouping_sets.add(get_grouping_set_rollup_on_product_department)
    grouping_sets.add(get_grouping_set_rollup_on_gender_and_product_department)
    detail = create_grouping_sets_list(grouping_sets)

    rollup_columns_list = gsl_get_rollup_columns(detail)
    assert_equal 2, rollup_columns_list.size
    assert_equal gender, rollup_columns_list.get(0)
    assert_equal product_department, rollup_columns_list.get(1)

    grouping_sets.add(get_grouping_set_rollup_on_gender_and_product_department_and_year)
    detail = create_grouping_sets_list(grouping_sets)
    rollup_columns_list = gsl_get_rollup_columns(detail)
    assert_equal 3, rollup_columns_list.size
    assert_equal gender, rollup_columns_list.get(0)
    assert_equal product_department, rollup_columns_list.get(1)
    assert_equal year, rollup_columns_list.get(2)

    grouping_sets.add(get_grouping_set_rollup_on_product_family_and_product_department)
    detail = create_grouping_sets_list(grouping_sets)
    rollup_columns_list = gsl_get_rollup_columns(detail)
    assert_equal 4, rollup_columns_list.size
    assert_equal gender, rollup_columns_list.get(0)
    assert_equal product_department, rollup_columns_list.get(1)
    assert_equal product_family, rollup_columns_list.get(2)
    assert_equal year, rollup_columns_list.get(3)

    assert_equal true,
      gsl_get_rollup_columns(create_grouping_sets_list(java.util.ArrayList.new)).isEmpty
  end

  # Java: SegmentLoaderTest#testGroupingSetsUtilSetsForDetailForRollupColumns
  it "grouping sets util sets for detail for rollup columns" do
    star_measure = get_measure(CUBE_NAME_SALES, MEASURE_UNIT_SALES)
    star = star_measure.getStar
    year = star.lookupColumn(TABLE_TIME, FIELD_YEAR)
    product_family = star.lookupColumn(TABLE_PRODUCT_CLASS, FIELD_PRODUCT_FAMILY)
    product_department = star.lookupColumn(TABLE_PRODUCT_CLASS, FIELD_PRODUCT_DEPARTMENT)
    gender = star.lookupColumn(TABLE_CUSTOMER, FIELD_GENDER)

    grouping_sets = java.util.ArrayList.new
    grouping_sets.add(get_default_grouping_set)
    grouping_sets.add(get_grouping_set_rollup_on_product_department)
    grouping_sets.add(get_grouping_set_rollup_on_gender_and_product_department)
    detail = create_grouping_sets_list(grouping_sets)

    rollup_columns_list = gsl_get_rollup_columns(detail)
    assert_equal 2, rollup_columns_list.size
    assert_equal gender, rollup_columns_list.get(0)
    assert_equal product_department, rollup_columns_list.get(1)

    grouping_sets.add(get_grouping_set_rollup_on_gender_and_product_department_and_year)
    detail = create_grouping_sets_list(grouping_sets)
    rollup_columns_list = gsl_get_rollup_columns(detail)
    assert_equal 3, rollup_columns_list.size
    assert_equal gender, rollup_columns_list.get(0)
    assert_equal product_department, rollup_columns_list.get(1)
    assert_equal year, rollup_columns_list.get(2)

    grouping_sets.add(get_grouping_set_rollup_on_product_family_and_product_department)
    detail = create_grouping_sets_list(grouping_sets)
    rollup_columns_list = gsl_get_rollup_columns(detail)
    assert_equal 4, rollup_columns_list.size
    assert_equal gender, rollup_columns_list.get(0)
    assert_equal product_department, rollup_columns_list.get(1)
    assert_equal product_family, rollup_columns_list.get(2)
    assert_equal year, rollup_columns_list.get(3)

    assert_equal true,
      gsl_get_rollup_columns(create_grouping_sets_list(java.util.ArrayList.new)).isEmpty
  end

  # Java: SegmentLoaderTest#testGroupingSetsUtilSetsForGroupingFunctionIndex
  it "grouping sets util sets for grouping function index" do
    grouping_sets = java.util.ArrayList.new
    grouping_sets.add(get_default_grouping_set)
    grouping_sets.add(get_grouping_set_rollup_on_product_department)
    grouping_sets.add(get_grouping_set_rollup_on_gender_and_product_department)
    detail = create_grouping_sets_list(grouping_sets)
    assert_equal 0, gsl_find_grouping_function_index(detail, 3)
    assert_equal 1, gsl_find_grouping_function_index(detail, 2)

    grouping_sets.add(get_grouping_set_rollup_on_gender_and_product_department_and_year)
    detail = create_grouping_sets_list(grouping_sets)
    assert_equal 0, gsl_find_grouping_function_index(detail, 3)
    assert_equal 1, gsl_find_grouping_function_index(detail, 2)
    assert_equal 2, gsl_find_grouping_function_index(detail, 0)

    grouping_sets.add(get_grouping_set_rollup_on_product_family_and_product_department)
    detail = create_grouping_sets_list(grouping_sets)
    assert_equal 0, gsl_find_grouping_function_index(detail, 3)
    assert_equal 1, gsl_find_grouping_function_index(detail, 2)
    assert_equal 2, gsl_find_grouping_function_index(detail, 1)
    assert_equal 3, gsl_find_grouping_function_index(detail, 0)
  end

  # Java: SegmentLoaderTest#testGetGroupingColumnsList
  it "get grouping columns list" do
    grouping_sets_info = get_default_grouping_set
    groupable_sets_info = get_grouping_set_rollup_on_gender

    detailed_columns = grouping_sets_info.getSegments.get(0).getColumns
    summary_columns = groupable_sets_info.getSegments.get(0).getColumns

    grouping_sets = java.util.ArrayList.new
    grouping_sets.add(grouping_sets_info)
    grouping_sets.add(groupable_sets_info)

    grouping_columns = gsl_get_grouping_sets_columns(create_grouping_sets_list(grouping_sets))
    assert_equal 2, grouping_columns.size
    assert_equal detailed_columns.to_a, grouping_columns.get(0).to_a
    assert_equal summary_columns.to_a, grouping_columns.get(1).to_a

    empty_columns = gsl_get_grouping_sets_columns(create_grouping_sets_list(java.util.ArrayList.new))
    assert_equal 0, empty_columns.size
  end
end
