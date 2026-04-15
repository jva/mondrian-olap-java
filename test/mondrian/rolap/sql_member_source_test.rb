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

# Java: mondrian/rolap/SqlMemberSourceTest.java
describe "SqlMemberSource" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # -- Reflection helpers --

  def find_declared_field(java_class, field_name)
    cls = java_class
    cls = cls.java_class if cls.respond_to?(:java_class) && !cls.is_a?(java.lang.Class)
    while cls
      begin
        field = cls.getDeclaredField(field_name)
        field.setAccessible(true)
        return field
      rescue java.lang.NoSuchFieldException
        cls = cls.getSuperclass
      end
    end
    raise "Field '#{field_name}' not found on #{java_class}"
  end

  def get_field(object, field_name)
    find_declared_field(object.getClass, field_name).get(object)
  end

  # Get the raw RolapHierarchy for a named hierarchy in the Sales cube.
  def get_store_hierarchy
    cube = @olap.raw_mondrian_connection.getSchema.lookupCube("Sales", true)
    hierarchy = cube.lookupHierarchy(
      Java::MondrianOlap::Id::NameSegment.new("Store", Java::MondrianOlap::Id::Quoting::UNQUOTED),
      false
    )
    # Get the shared RolapHierarchy (unwrap CubeHierarchy)
    hierarchy.respond_to?(:getRolapHierarchy) ? hierarchy.getRolapHierarchy : hierarchy
  end

  # Get the SqlMemberSource from a hierarchy's member reader chain.
  # The hierarchy's memberReader is typically a SmartMemberReader wrapping a SqlMemberSource.
  def get_sql_member_source(hierarchy)
    member_reader = get_field(hierarchy, "memberReader")
    # SmartMemberReader has a "source" field that holds the SqlMemberSource
    get_field(member_reader, "source")
  end

  # Find the Store City level (depth 3 in FoodMart's Store hierarchy: All=0, Country=1, State=2, City=3).
  def get_level_by_name(hierarchy, level_name)
    hierarchy.getLevels.to_a.detect { |level| level.getName == level_name }
  end

  # Invoke the private makeLevelMemberCountSql method on a SqlMemberSource via reflection.
  def invoke_make_level_member_count_sql(sql_member_source, level, data_source, must_count)
    rolap_level_class = level.getClass
    data_source_class = javax.sql.DataSource.java_class
    boolean_array_class = must_count.java_class

    method = nil
    cls = sql_member_source.getClass
    while cls
      begin
        method = cls.getDeclaredMethod(
          "makeLevelMemberCountSql",
          [rolap_level_class, data_source_class, boolean_array_class].to_java(java.lang.Class)
        )
        break
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end
    raise "makeLevelMemberCountSql method not found" unless method
    method.setAccessible(true)
    method.invoke(sql_member_source, level, data_source, must_count)
  end

  # Java: SqlMemberSourceTest#testMakeLevelMemberCountSql
  it "generates member count SQL for a level" do
    hierarchy = get_store_hierarchy
    sql_member_source = get_sql_member_source(hierarchy)
    city_level = get_level_by_name(hierarchy, "Store City")
    refute_nil city_level, "Store City level not found"

    data_source = @olap.raw_mondrian_connection.getDataSource
    must_count = [false].to_java(:boolean)

    result = invoke_make_level_member_count_sql(sql_member_source, city_level, data_source, must_count)
    refute_nil result

    # The Java test uses a mocked MySQL 3.x data source (before version 4), which triggers
    # the compound COUNT DISTINCT path (allowsFromQuery=false, allowsCompoundCountDistinct=true):
    #   select count(DISTINCT `store`.`store_city`, `store`.`store_state`, `store`.`store_country`) as `c0`
    #
    # With a real database connection (modern MySQL 4+ or PostgreSQL), allowsFromQuery returns true,
    # so the method takes the FROM-subquery path instead.
    #
    # FoodMart's Store hierarchy: Store Country (unique) > Store State (unique) > Store City (not unique).
    # The iteration walks from City back through ancestors, stopping at the first unique level.
    # Store City is not unique, Store State IS unique, so columns are: store_city, store_state.
    normalized = result.gsub(/\s+/, " ").strip

    # Verify the outer count(*) wrapper and the inner DISTINCT subquery structure
    assert_match(/select count\(\*\)/i, normalized)
    assert_match(/select distinct/i, normalized)
    assert_match(/store_city/i, normalized)
    assert_match(/store_state/i, normalized)
    # The SQL should NOT include store_country because Store State is uniqueMembers=true,
    # which causes the iteration to stop before reaching Store Country.
    refute_match(/store_country/i, normalized)
    assert_equal false, must_count[0]
  end
end
