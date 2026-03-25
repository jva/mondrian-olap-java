# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2007-2008 Bart Pappyn
# Copyright (C) 2007-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# SQL logger that tracks queries, filtering out count requests generated
# by the segment builder (which are not deterministic across queries).
class ChangeListenerSqlLogger
  include Java::MondrianRolap::RolapUtil::ExecuteQueryHook

  def initialize
    @sql_queries = []
  end

  def clear
    @sql_queries.clear
  end

  def sql_queries
    @sql_queries.dup
  end

  def onExecuteQuery(sql)
    @sql_queries << sql unless sql.start_with?("select count(")
  end
end

# Java: mondrian/rolap/DataSourceChangeListenerTest.java
describe "DataSourceChangeListener" do
  before(:all) do
    Mondrian::OLAP::Connection.flush_schema_cache
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
    Mondrian::OLAP::Connection.flush_schema_cache
  end

  def internal_connection
    @olap.raw_mondrian_connection
  end

  # --- Reflection helpers ---

  def find_field(object, field_name)
    cls = object.java_class
    while cls
      begin
        field = cls.getDeclaredField(field_name)
        field.setAccessible(true)
        return field
      rescue java.lang.NoSuchFieldException
        cls = cls.getSuperclass
      end
    end
    raise "Field '#{field_name}' not found on #{object.java_class.getName}"
  end

  def get_field(object, field_name)
    find_field(object, field_name).get(object)
  end

  def set_field(object, field_name, value)
    find_field(object, field_name).set(object, value)
  end

  def find_method(object, method_name, param_types = [])
    cls = object.java_class
    while cls
      begin
        method = cls.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
        method.setAccessible(true)
        return method
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end
    raise "Method '#{method_name}' not found on #{object.java_class.getName}"
  end

  def invoke_method(object, method_name, param_types, *args)
    find_method(object, method_name, param_types).invoke(object, *args)
  rescue java.lang.reflect.InvocationTargetException => e
    raise e.cause
  end

  # Get SmartMemberReader for a hierarchy in the Sales cube.
  # Equivalent to Java getSmartMemberReader(connection, hierName).
  def get_smart_member_reader(hierarchy_name)
    cube = internal_connection.getSchema.lookupCube("Sales", true)
    schema_reader = cube.getSchemaReader
    hierarchy = cube.lookupHierarchy(
      Java::MondrianOlap::Id::NameSegment.new(hierarchy_name, Java::MondrianOlap::Id::Quoting::UNQUOTED),
      false
    )
    refute_nil hierarchy
    invoke_method(hierarchy, "createMemberReader", [Java::MondrianOlap::Role.java_class], schema_reader.getRole)
  end

  # Get shared SmartMemberReader for a hierarchy.
  # Equivalent to Java getSharedSmartMemberReader(connection, hierName).
  def get_shared_smart_member_reader(hierarchy_name)
    cube = internal_connection.getSchema.lookupCube("Sales", true)
    schema_reader = cube.getSchemaReader
    hierarchy = cube.lookupHierarchy(
      Java::MondrianOlap::Id::NameSegment.new(hierarchy_name, Java::MondrianOlap::Id::Quoting::UNQUOTED),
      false
    )
    refute_nil hierarchy
    shared_hierarchy = hierarchy.getRolapHierarchy
    invoke_method(shared_hierarchy, "createMemberReader", [Java::MondrianOlap::Role.java_class], schema_reader.getRole)
  end

  # Get RolapStar for a named cube.
  def get_star(cube_name)
    cube = internal_connection.getSchema.lookupCube(cube_name, true)
    cube.getStar
  end

  # Clear and harden cache: replace soft caches with hard caches for deterministic testing.
  # Equivalent to Java clearAndHardenCache(MemberCacheHelper).
  def clear_and_harden_cache(helper)
    smart_cache_class = Java::MondrianRolapCache::SmartCache.java_class

    map_level = get_field(helper, "mapLevelToMembers")
    invoke_method(map_level, "setCache", [smart_cache_class], Java::MondrianRolapCache::HardSmartCache.new)

    map_children = get_field(helper, "mapMemberToChildren")
    invoke_method(map_children, "setCache", [smart_cache_class], Java::MondrianRolapCache::HardSmartCache.new)

    get_field(helper, "mapKeyToMember").clear

    map_named = get_field(helper, "mapParentToNamedChildren")
    invoke_method(map_named, "setCache", [smart_cache_class], Java::MondrianRolapCache::HardSmartCache.new)
  end

  def set_change_listener(helper, listener)
    set_field(helper, "changeListener", listener)
  end

  # Java: DataSourceChangeListenerTest#testDataSourceChangeListenerPlugin
  it "data source change listener plugin controls cache behavior" do
    properties = Java::MondrianOlap::MondrianProperties.instance
    # Dependency testing produces side-effects in the cache.
    skip if properties.TestExpDependencies.get > 0

    # Flush the entire cell cache
    cache_control = internal_connection.getCacheControl(nil)
    sales_cube = internal_connection.getSchema.lookupCube("Sales", true)
    measures_region = cache_control.createMeasuresRegion(sales_cube)
    cache_control.flush(measures_region)

    with_properties(DisableCaching: false) do
      cache_control.flushSchemaCache

      # Get member readers and cache helpers
      smr = get_smart_member_reader("Store")
      smr_cache_helper = smr.getMemberCache
      rcsmr_cache_helper = smr.getRolapCubeMemberCacheHelper
      ssmr = get_shared_smart_member_reader("Store")
      ssmr_cache_helper = ssmr.getMemberCache

      # Use hard caching for testing. When using soft references, we can not
      # test caching because things may be garbage collected during the tests.
      clear_and_harden_cache(ssmr_cache_helper)
      clear_and_harden_cache(rcsmr_cache_helper)
      clear_and_harden_cache(smr_cache_helper)

      sql_logger = ChangeListenerSqlLogger.new
      Java::MondrianRolap::RolapUtil.setHook(sql_logger)

      begin
        mdx = "select {[Store].[All Stores].[USA].[CA].[San Francisco]} on columns from [Sales]"

        # Flush the cache, to ensure that the query gets executed.
        @olap.execute(mdx)
        s1 = sql_logger.sql_queries.to_s
        sql_logger.clear
        # s1 should not be empty
        refute_equal "[]", s1, "First query should generate SQL"

        # Run query again, to make sure only cache is used
        @olap.execute(mdx)
        s2 = sql_logger.sql_queries.to_s
        sql_logger.clear
        assert_equal "[]", s2

        # Attach dummy change listener that tells mondrian the
        # datasource is never changed.
        listener_never_changed = Java::MondrianSpiImpl::DataSourceChangeListenerImpl.new
        set_change_listener(smr_cache_helper, listener_never_changed)
        set_change_listener(ssmr_cache_helper, listener_never_changed)
        set_change_listener(rcsmr_cache_helper, listener_never_changed)

        # Run query again, to make sure only cache is used
        @olap.execute(mdx)
        s3 = sql_logger.sql_queries.to_s
        sql_logger.clear
        assert_equal "[]", s3

        # Manually clear the cache to make compare sql result later on
        clear_and_harden_cache(smr_cache_helper)
        clear_and_harden_cache(ssmr_cache_helper)
        clear_and_harden_cache(rcsmr_cache_helper)

        # Run query again — must re-fetch from database
        @olap.execute(mdx)
        s4 = sql_logger.sql_queries.to_s
        sql_logger.clear
        refute_equal "[]", s4, "Query after cache clear should generate SQL"

        # Attach dummy change listener that tells mondrian the
        # datasource is always changed.
        listener_always_changed = Java::MondrianSpiImpl::DataSourceChangeListenerImpl2.new
        set_change_listener(smr_cache_helper, listener_always_changed)
        set_change_listener(ssmr_cache_helper, listener_always_changed)
        set_change_listener(rcsmr_cache_helper, listener_always_changed)

        # Run query again — should generate same SQL as after manual cache clear
        @olap.execute(mdx)
        s5 = sql_logger.sql_queries.to_s
        sql_logger.clear
        assert_equal s4, s5

        # Attach dummy change listener that tells mondrian the datasource
        # is always changed and tells that aggregate cache is always changed.
        listener_all_changed = Java::MondrianSpiImpl::DataSourceChangeListenerImpl3.new
        set_change_listener(smr_cache_helper, listener_all_changed)
        set_change_listener(ssmr_cache_helper, listener_all_changed)
        set_change_listener(rcsmr_cache_helper, listener_all_changed)

        star = get_star("Sales")
        star.setChangeListener(listener_all_changed)

        # Run query again — should generate same SQL as original first query
        @olap.execute(mdx)
        s6 = sql_logger.sql_queries.to_s
        sql_logger.clear
        assert_equal s1, s6
      ensure
        set_change_listener(smr_cache_helper, nil)
        set_change_listener(ssmr_cache_helper, nil)
        set_change_listener(rcsmr_cache_helper, nil)

        star = get_star("Sales")
        star.setChangeListener(nil)

        Java::MondrianRolap::RolapUtil.setHook(nil)
      end
    end
  end
end
