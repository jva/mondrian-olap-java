# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

RETAIL_DIMENSION_XML = <<~XML
  <Dimension name="Retail" foreignKey="store_id">
    <Hierarchy hasAll="true" primaryKey="store_id">
      <Table name="store"/>
      <Level name="State" column="store_state" uniqueMembers="true">
        <Property name="Country" column="store_country"/>
      </Level>
      <Level name="City" column="store_city" uniqueMembers="true">
        <Property name="Population" column="store_postal_code"/>
      </Level>
      <Level name="Name" column="store_name" uniqueMembers="true">
        <Property name="Store Type" column="store_type"/>
        <Property name="Store Manager" column="store_manager"/>
        <Property name="Store Sqft" column="store_sqft" type="Numeric"/>
        <Property name="Has coffee bar" column="coffee_bar" type="Boolean"/>
        <Property name="Street address" column="store_street_address" type="String"/>
      </Level>
    </Hierarchy>
  </Dimension>
XML

# Java: mondrian/rolap/MemberCacheControlTest.java
describe "MemberCacheControl" do
  def create_retail_connection
    connection_with_modified_cube("Sales", dimensions: RETAIL_DIMENSION_XML)
  end

  def internal_connection(olap)
    olap.raw_mondrian_connection
  end

  def find_member(olap, cube_name, *names)
    connection = internal_connection(olap)
    cube = connection.getSchema.lookupCube(cube_name, true)
    schema_reader = cube.getSchemaReader(nil).withLocus
    ids = Java::MondrianOlap::Id::Segment.toList(*names)
    schema_reader.getMemberByUniqueName(ids, true)
  end

  def get_cache_control(olap)
    internal_connection(olap).getCacheControl(nil)
  end

  def with_locus(olap)
    connection = internal_connection(olap)
    statement = connection.getInternalStatement
    begin
      execution = Java::MondrianServer::Execution.new(statement, 0)
      locus = Java::MondrianServer::Locus.new(execution, "MemberCacheControlTest", nil)
      Java::MondrianServer::Locus.push(locus)
      begin
        yield
      ensure
        Java::MondrianServer::Locus.pop(locus)
      end
    ensure
      statement.close
    end
  end

  # Access the package-private .member field on RolapCubeMember via reflection.
  # The field is defined on DelegatingRolapMember (superclass), so traverse the hierarchy.
  def unwrap_cube_member(cube_member)
    cls = cube_member.getClass
    while cls
      begin
        field = cls.getDeclaredField("member")
        field.setAccessible(true)
        return field.get(cube_member)
      rescue Java::JavaLang::NoSuchFieldException
        cls = cls.getSuperclass
      end
    end
    raise "field 'member' not found in class hierarchy of #{cube_member.getClass.getName}"
  end

  # Access the package-private getMemberReader() on RolapHierarchy via reflection.
  def get_member_reader(hierarchy)
    method = hierarchy.getClass.getMethod("getMemberReader")
    method.setAccessible(true)
    method.invoke(hierarchy)
  end

  # Access getMemberCache() on SmartMemberReader via reflection.
  def get_member_cache(member_reader)
    method = member_reader.getClass.getMethod("getMemberCache")
    method.setAccessible(true)
    method.invoke(member_reader)
  end

  # Access getChildrenFromCache on MemberCache via reflection.
  def get_children_from_cache(member_cache, member)
    class_loader = member_cache.getClass.getClassLoader
    cls = member_cache.getClass
    method = nil
    while cls
      begin
        param_types = [
          java.lang.Class.forName("mondrian.rolap.RolapMember", true, class_loader),
          java.lang.Class.forName("mondrian.rolap.sql.MemberChildrenConstraint", true, class_loader)
        ].to_java(java.lang.Class)
        method = cls.getDeclaredMethod("getChildrenFromCache", param_types)
        break
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end
    raise "getChildrenFromCache not found" unless method
    method.setAccessible(true)
    method.invoke(member_cache, member, nil)
  end

  # Get AggregationManager from the connection's server.
  def get_aggregation_manager(olap)
    connection = internal_connection(olap)
    server = connection.getServer
    server.getAggregationManager
  end

  # Print member properties in the same format as the Java test.
  def print_member_properties(member)
    result = +"#{member.getUniqueName} {"
    properties = member.getLevel.getProperties
    properties.each_with_index do |property, index|
      result << "," if index > 0
      result << "\n"
      name = property.getName
      value = member.getPropertyValue(name)
      # Fixup value for different database representations
      if !value.nil?
        if name == "Has coffee bar"
          value = value.to_i != 0 if value.is_a?(Numeric) || value.respond_to?(:intValue)
          if value.respond_to?(:intValue)
            value = value.intValue != 0
          end
        elsif name.end_with?(" Sqft")
          if value.respond_to?(:intValue)
            value = value == value.intValue ? value.intValue : value.floatValue.round
          end
        end
      end
      result << "  [#{name}]=[#{value.nil? ? 'null' : value}]"
    end
    result << "}\n"
    result
  end

  # Print properties for all members on the row axis of an internal Result.
  def get_row_member_properties_string(result)
    rows_axis = result.getAxes[1]
    output = +""
    rows_axis.getPositions.each do |position|
      position.each do |member|
        output << print_member_properties(member)
        output << "\n"
      end
    end
    output
  end

  # Format an internal Result to string (same as Java TestContext.toString).
  def format_internal_result(result)
    string_writer = Java::JavaIo::StringWriter.new
    print_writer = Java::JavaIo::PrintWriter.new(string_writer)
    result.print(print_writer)
    print_writer.flush
    string_writer.toString
  end

  # Execute MDX via the internal API and return mondrian.olap.Result.
  def execute_internal(olap, mdx)
    connection = internal_connection(olap)
    query = connection.parseQuery(mdx)
    connection.execute(query)
  end

  # Assert full query result matches expected (using internal API).
  def assert_internal_query_returns(olap, mdx, expected)
    result = execute_internal(olap, mdx)
    actual = format_internal_result(result)
    assert_like expected, actual
  end

  # Assert axis returns expected members (using internal API).
  def assert_internal_axis_returns(olap, expression, expected)
    mdx = "SELECT {#{expression}} ON 0 FROM [Sales]"
    result = execute_internal(olap, mdx)
    axis = result.getAxes[0]
    lines = axis.getPositions.map do |position|
      position.map { |m| m.getUniqueName }.join(", ")
    end
    assert_equal expected.strip, lines.join("\n").strip
  end

  # Create the union member set used by testFilter and testSetPropertyCommandOnNonLeafMember.
  def create_interesting_member_set(olap, cache_control)
    cache_control.createUnionSet(
      # all stores in OR
      cache_control.createMemberSet(find_member(olap, "Sales", "Retail", "OR"), true),
      # all stores in Hidalgo, Zacatecas
      cache_control.createMemberSet(
        find_member(olap, "Sales", "Retail", "Zacatecas", "Hidalgo"), true),
      # a single store
      cache_control.createMemberSet(
        find_member(olap, "Sales", "Retail", "CA", "Alameda", "HQ"), false),
      # a range of stores
      cache_control.createMemberSet(
        true, find_member(olap, "Sales", "Retail", "WA", "Bremerton"),
        true, find_member(olap, "Sales", "Retail", "Yucatan", "Merida"),
        false),
      # all stores in a range of states
      cache_control.createMemberSet(
        true, find_member(olap, "Sales", "Retail", "DF"),
        true, find_member(olap, "Sales", "Retail", "Jalisco"),
        true)
    )
  end

  # Clear the schema pool via reflection (package-private).
  def clear_schema_pool
    pool_class = java.lang.Class.forName(
      "mondrian.rolap.RolapSchemaPool", true,
      Java::MondrianRolap::RolapUtil.java_class.getClassLoader
    )
    instance_method = pool_class.getDeclaredMethod("instance")
    instance_method.setAccessible(true)
    pool = instance_method.invoke(nil)
    clear_method = pool_class.getDeclaredMethod("clear")
    clear_method.setAccessible(true)
    clear_method.invoke(pool)
  end

  # Java: MemberCacheControlTest#testFilter
  it "filters member set by level" do
    with_properties(EnableRolapCubeMemberCache: false) do
      clear_schema_pool
      olap = create_retail_connection
      begin
        with_locus(olap) do
          cache_control = get_cache_control(olap)
          member_set = create_interesting_member_set(olap, cache_control)

          expected_before = "Union(Member([Retail].[OR]), " \
            "Member([Retail].[Zacatecas].[Hidalgo]), " \
            "Member([Retail].[CA].[Alameda].[HQ]), " \
            "Range([Retail].[WA].[Bremerton] inclusive to [Retail].[Yucatan].[Merida] inclusive), " \
            "Range([Retail].[DF] inclusive to [Retail].[Jalisco] inclusive))"
          assert_equal expected_before, member_set.toString

          or_member = find_member(olap, "Sales", "Retail", "OR")
          filtered_member_set = cache_control.filter(or_member.getLevel, member_set)

          expected_after = "Union(Member([Retail].[OR]), " \
            "Range([Retail].[DF] inclusive to [Retail].[Jalisco] inclusive))"
          assert_equal expected_after, filtered_member_set.toString
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  # Java: MemberCacheControlTest#testMemberOpsFailIfCacheEnabled
  it "member operations fail if cache is enabled" do
    with_properties(EnableRolapCubeMemberCache: true) do
      clear_schema_pool
      olap = create_retail_connection
      begin
        with_locus(olap) do
          cache_control = get_cache_control(olap)
          command = cache_control.createDeleteCommand(find_member(olap, "Sales", "Retail", "OR"))

          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.execute(command)
          end
          assert_equal(
            "Member cache control operations are not allowed unless " \
            "property mondrian.rolap.EnableRolapCubeMemberCache is false",
            error.message
          )
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  # Java: MemberCacheControlTest#testSetPropertyCommandOnLeafMember
  it "sets properties on a leaf member" do
    with_properties(EnableRolapCubeMemberCache: false) do
      clear_schema_pool
      olap = create_retail_connection
      begin
        with_locus(olap) do
          connection = internal_connection(olap)
          cache_control = get_cache_control(olap)

          mdx = "SELECT {[Measures].[Unit Sales]} ON COLUMNS," \
            " {[Store].[USA].[CA].[San Francisco].[Store 14]} ON ROWS FROM [Sales]"
          query = connection.parseQuery(mdx)
          result = connection.execute(query)

          props_before = get_row_member_properties_string(result)
          expected_props_before = <<~PROPS
            [Store].[USA].[CA].[San Francisco].[Store 14] {
              [Store Type]=[Small Grocery],
              [Store Manager]=[Strehlo],
              [Store Sqft]=[22478],
              [Grocery Sqft]=[15321],
              [Frozen Sqft]=[4294],
              [Meat Sqft]=[2863],
              [Has coffee bar]=[true],
              [Street address]=[4365 Indigo Ct]}
          PROPS
          assert_like expected_props_before, props_before

          result_before = format_internal_result(result)

          # Change properties
          member = find_member(olap, "Sales", "Store", "USA", "CA", "San Francisco", "Store 14")
          cache_control.execute(cache_control.createSetPropertyCommand(member, "Store Manager", "Higgins"))
          cache_control.execute(
            cache_control.createCompoundCommand(
              java.util.Arrays.asList(
                cache_control.createSetPropertyCommand(member, "Street address", "770 Mission St"),
                cache_control.createSetPropertyCommand(member, "Store Sqft", 6000),
                cache_control.createSetPropertyCommand(member, "Has coffee bar", "false")
              )
            )
          )

          # Repeat same query; verify properties are changed
          result = connection.execute(query)
          props_after = get_row_member_properties_string(result)
          expected_props_after = <<~PROPS
            [Store].[USA].[CA].[San Francisco].[Store 14] {
              [Store Type]=[Small Grocery],
              [Store Manager]=[Higgins],
              [Store Sqft]=[6000],
              [Grocery Sqft]=[15321],
              [Frozen Sqft]=[4294],
              [Meat Sqft]=[2863],
              [Has coffee bar]=[false],
              [Street address]=[770 Mission St]}
          PROPS
          assert_like expected_props_after, props_after

          # Results should be unchanged (property changes don't affect measures)
          assert_equal result_before, format_internal_result(result)
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  # Java: MemberCacheControlTest#testSetPropertyCommandOnNonLeafMember
  it "sets properties on non-leaf members" do
    with_properties(EnableRolapCubeMemberCache: false) do
      clear_schema_pool
      olap = create_retail_connection
      begin
        with_locus(olap) do
          connection = internal_connection(olap)
          cache_control = get_cache_control(olap)

          mdx = "SELECT {[Measures].[Unit Sales]} ON COLUMNS," \
            " {[Retail].Members} ON ROWS FROM [Sales]"
          query = connection.parseQuery(mdx)
          result = connection.execute(query)

          props_before = get_row_member_properties_string(result)
          # Verify a representative subset of the before properties
          assert_includes props_before, "[Retail].[CA].[Alameda].[HQ]"
          assert_includes props_before, "[Store Sqft]=[null]"
          assert_includes props_before, "[Has coffee bar]=[false]"
          # HQ's original values for the properties we'll change
          assert_match(/\[Retail\]\.\[CA\]\.\[Alameda\]\.\[HQ\] \{.*\[Has coffee bar\]=\[false\]/m, props_before)

          result_before = format_internal_result(result)

          # The member set contains members of various levels
          member_set = create_interesting_member_set(olap, cache_control)

          property_values = java.util.HashMap.new
          property_values.put("Has coffee bar", "true")
          property_values.put("Store Sqft", 123)

          # First, the member set contains members of various levels — should fail
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.createSetPropertyCommand(member_set, property_values)
          end
          assert_equal "all members in set must belong to same level", error.message

          # After filtering to store level we're ok
          hq_member = find_member(olap, "Sales", "Retail", "CA", "Alameda", "HQ")
          filtered_member_set = cache_control.filter(hq_member.getLevel, member_set)
          command = cache_control.createSetPropertyCommand(filtered_member_set, property_values)
          cache_control.execute(command)

          # Repeat same query; verify properties were changed
          result = connection.execute(query)
          props_after = get_row_member_properties_string(result)

          # HQ should have changed properties (was [Has coffee bar]=[false], now [true]; was [Store Sqft]=[null], now [123])
          assert_match(/\[Retail\]\.\[CA\]\.\[Alameda\]\.\[HQ\] \{.*\[Store Sqft\]=\[123\].*\[Has coffee bar\]=\[true\]/m, props_after)

          # Stores in the filtered set (DF, Guerrero, Jalisco ranges; OR members) should also have changed
          # Store 9 in DF was [Has coffee bar]=[false], [Store Sqft]=[36509] — now should be [true], [123]
          assert_match(/\[Retail\]\.\[DF\]\.\[Mexico City\]\.\[Store 9\] \{.*\[Store Sqft\]=\[123\].*\[Has coffee bar\]=\[true\]/m, props_after)

          # Stores NOT in the filtered set should be unchanged (e.g., Store 6 in Beverly Hills)
          assert_match(/\[Retail\]\.\[CA\]\.\[Beverly Hills\]\.\[Store 6\] \{.*\[Store Sqft\]=\[23688\].*\[Has coffee bar\]=\[true\]/m, props_after)

          # Results should be unchanged (property changes don't affect measures)
          assert_equal result_before, format_internal_result(result)
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  # Java: MemberCacheControlTest#testAddCommand
  it "adds a new member to the cache" do
    with_properties(EnableRolapCubeMemberCache: false) do
      clear_schema_pool
      olap = create_retail_connection
      begin
        with_locus(olap) do
          cache_control = get_cache_control(olap)
          ca_cube_member = find_member(olap, "Sales", "Retail", "CA")
          ca_member = unwrap_cube_member(ca_cube_member)
          root_member = ca_member.getParentMember
          hierarchy = ca_member.getHierarchy

          berkeley_member = hierarchy.createMember(
            ca_member,
            ca_member.getLevel.getChildLevel,
            "Berkeley",
            nil
          )

          unit_sales_cube_member = find_member(olap, "Sales", "Measures", "Unit Sales")
          year_cube_member = find_member(olap, "Sales", "Time", "Year", "1997")
          cache_region_members = [unit_sales_cube_member, ca_cube_member, year_cube_member].to_java(Java::MondrianOlap::Member)

          # Verify initial city members query
          assert_internal_query_returns olap,
            "select {[Retail].[City].Members} on columns from [Sales]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Retail].[BC].[Vancouver]}
              {[Retail].[BC].[Victoria]}
              {[Retail].[CA].[Alameda]}
              {[Retail].[CA].[Beverly Hills]}
              {[Retail].[CA].[Los Angeles]}
              {[Retail].[CA].[San Diego]}
              {[Retail].[CA].[San Francisco]}
              {[Retail].[DF].[Mexico City]}
              {[Retail].[DF].[San Andres]}
              {[Retail].[Guerrero].[Acapulco]}
              {[Retail].[Jalisco].[Guadalajara]}
              {[Retail].[OR].[Portland]}
              {[Retail].[OR].[Salem]}
              {[Retail].[Veracruz].[Orizaba]}
              {[Retail].[WA].[Bellingham]}
              {[Retail].[WA].[Bremerton]}
              {[Retail].[WA].[Seattle]}
              {[Retail].[WA].[Spokane]}
              {[Retail].[WA].[Tacoma]}
              {[Retail].[WA].[Walla Walla]}
              {[Retail].[WA].[Yakima]}
              {[Retail].[Yucatan].[Merida]}
              {[Retail].[Zacatecas].[Camacho]}
              {[Retail].[Zacatecas].[Hidalgo]}
              Row #0:
              Row #0:
              Row #0:
              Row #0: 21,333
              Row #0: 25,663
              Row #0: 25,635
              Row #0: 2,117
              Row #0:
              Row #0:
              Row #0:
              Row #0:
              Row #0: 26,079
              Row #0: 41,580
              Row #0:
              Row #0: 2,237
              Row #0: 24,576
              Row #0: 25,011
              Row #0: 23,591
              Row #0: 35,257
              Row #0: 2,203
              Row #0: 11,491
              Row #0:
              Row #0:
              Row #0:
            RESULT

          assert_internal_axis_returns olap, "[Retail].[CA].Children",
            "[Retail].[CA].[Alameda]\n" \
            "[Retail].[CA].[Beverly Hills]\n" \
            "[Retail].[CA].[Los Angeles]\n" \
            "[Retail].[CA].[San Diego]\n" \
            "[Retail].[CA].[San Francisco]"

          member_reader = get_member_reader(hierarchy)
          member_cache = get_member_cache(member_reader)
          ca_children = get_children_from_cache(member_cache, ca_member)
          assert_equal 5, ca_children.size

          # Load cell data and check it is in cache
          execute_internal(olap, "select {[Measures].[Unit Sales]} on columns, {[Retail].[CA]} on rows from [Sales]")
          aggregation_manager = get_aggregation_manager(olap)
          cell_value = aggregation_manager.getCellFromAllCaches(
            Java::MondrianRolapAgg::AggregationManager.makeRequest(cache_region_members)
          )
          assert_equal 74_748.0, cell_value.doubleValue

          # Now tell the cache that [CA].[Berkeley] is new
          command = cache_control.createAddCommand(berkeley_member)
          cache_control.execute(command)

          # Test that cells have been removed
          assert_nil aggregation_manager.getCellFromAllCaches(
            Java::MondrianRolapAgg::AggregationManager.makeRequest(cache_region_members)
          )

          assert_internal_axis_returns olap, "[Retail].[CA].Children",
            "[Retail].[CA].[Alameda]\n" \
            "[Retail].[CA].[Beverly Hills]\n" \
            "[Retail].[CA].[Los Angeles]\n" \
            "[Retail].[CA].[San Diego]\n" \
            "[Retail].[CA].[San Francisco]\n" \
            "[Retail].[CA].[Berkeley]"

          # City members query should now include Berkeley
          assert_internal_query_returns olap,
            "select {[Retail].[City].Members} on columns from [Sales]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Retail].[BC].[Vancouver]}
              {[Retail].[BC].[Victoria]}
              {[Retail].[CA].[Alameda]}
              {[Retail].[CA].[Berkeley]}
              {[Retail].[CA].[Beverly Hills]}
              {[Retail].[CA].[Los Angeles]}
              {[Retail].[CA].[San Diego]}
              {[Retail].[CA].[San Francisco]}
              {[Retail].[DF].[Mexico City]}
              {[Retail].[DF].[San Andres]}
              {[Retail].[Guerrero].[Acapulco]}
              {[Retail].[Jalisco].[Guadalajara]}
              {[Retail].[OR].[Portland]}
              {[Retail].[OR].[Salem]}
              {[Retail].[Veracruz].[Orizaba]}
              {[Retail].[WA].[Bellingham]}
              {[Retail].[WA].[Bremerton]}
              {[Retail].[WA].[Seattle]}
              {[Retail].[WA].[Spokane]}
              {[Retail].[WA].[Tacoma]}
              {[Retail].[WA].[Walla Walla]}
              {[Retail].[WA].[Yakima]}
              {[Retail].[Yucatan].[Merida]}
              {[Retail].[Zacatecas].[Camacho]}
              {[Retail].[Zacatecas].[Hidalgo]}
              Row #0:
              Row #0:
              Row #0:
              Row #0:
              Row #0: 21,333
              Row #0: 25,663
              Row #0: 25,635
              Row #0: 2,117
              Row #0:
              Row #0:
              Row #0:
              Row #0:
              Row #0: 26,079
              Row #0: 41,580
              Row #0:
              Row #0: 2,237
              Row #0: 24,576
              Row #0: 25,011
              Row #0: 23,591
              Row #0: 35,257
              Row #0: 2,203
              Row #0: 11,491
              Row #0:
              Row #0:
              Row #0:
            RESULT

          # State-level children should be unchanged
          assert_internal_query_returns olap,
            "select [Retail].Children on 0 from [Sales]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Retail].[BC]}
              {[Retail].[CA]}
              {[Retail].[DF]}
              {[Retail].[Guerrero]}
              {[Retail].[Jalisco]}
              {[Retail].[OR]}
              {[Retail].[Veracruz]}
              {[Retail].[WA]}
              {[Retail].[Yucatan]}
              {[Retail].[Zacatecas]}
              Row #0:
              Row #0: 74,748
              Row #0:
              Row #0:
              Row #0:
              Row #0: 67,659
              Row #0:
              Row #0: 124,366
              Row #0:
              Row #0:
            RESULT

          root_children = get_children_from_cache(member_cache, root_member)
          if root_children # might be null due to gc
            assert_equal 10, root_children.size
          end
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  # Java: MemberCacheControlTest#testDeleteCommand
  it "deletes a member from the cache" do
    with_properties(EnableRolapCubeMemberCache: false) do
      clear_schema_pool
      olap = create_retail_connection
      begin
        with_locus(olap) do
          cache_control = get_cache_control(olap)
          sf_cube_member = find_member(olap, "Sales", "Retail", "CA", "San Francisco")
          ca_member = unwrap_cube_member(sf_cube_member).getParentMember
          hierarchy = ca_member.getHierarchy

          unit_sales_cube_member = find_member(olap, "Sales", "Measures", "Unit Sales")
          year_cube_member = find_member(olap, "Sales", "Time", "Year", "1997")
          cache_region_members = [unit_sales_cube_member, sf_cube_member, year_cube_member].to_java(Java::MondrianOlap::Member)

          assert_internal_axis_returns olap, "[Retail].[CA].Children",
            "[Retail].[CA].[Alameda]\n" \
            "[Retail].[CA].[Beverly Hills]\n" \
            "[Retail].[CA].[Los Angeles]\n" \
            "[Retail].[CA].[San Diego]\n" \
            "[Retail].[CA].[San Francisco]"

          member_reader = get_member_reader(hierarchy)
          member_cache = get_member_cache(member_reader)
          ca_children = get_children_from_cache(member_cache, ca_member)
          assert_equal 5, ca_children.size

          # Load cell data and check it is in cache
          execute_internal(olap, "select {[Measures].[Unit Sales]} on columns, {[Retail].[CA].[Alameda]} on rows from [Sales]")
          aggregation_manager = get_aggregation_manager(olap)
          cell_value = aggregation_manager.getCellFromAllCaches(
            Java::MondrianRolapAgg::AggregationManager.makeRequest(cache_region_members)
          )
          assert_equal 2117.0, cell_value.doubleValue

          # Now tell the cache that [CA].[San Francisco] has been removed
          command = cache_control.createDeleteCommand(sf_cube_member)
          cache_control.execute(command)

          # Children of CA should be 4
          assert_equal 4, get_children_from_cache(member_cache, ca_member).size

          # Test that cells have been removed
          assert_nil aggregation_manager.getCellFromAllCaches(
            Java::MondrianRolapAgg::AggregationManager.makeRequest(cache_region_members)
          )

          # The list of children should be updated
          assert_internal_axis_returns olap, "[Retail].[CA].Children",
            "[Retail].[CA].[Alameda]\n" \
            "[Retail].[CA].[Beverly Hills]\n" \
            "[Retail].[CA].[Los Angeles]\n" \
            "[Retail].[CA].[San Diego]"
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  # Java: MemberCacheControlTest#testMoveCommand
  it "moves a member to a different parent" do
    with_properties(EnableRolapCubeMemberCache: false) do
      clear_schema_pool
      olap = create_retail_connection
      begin
        with_locus(olap) do
          cache_control = get_cache_control(olap)
          ca_cube_member = find_member(olap, "Sales", "Retail", "CA")
          ca_member = unwrap_cube_member(ca_cube_member)
          hierarchy = ca_member.getHierarchy

          alameda_member = hierarchy.createMember(
            ca_member, ca_member.getLevel.getChildLevel, "Alameda", nil)
          sf_member = hierarchy.createMember(
            ca_member, ca_member.getLevel.getChildLevel, "San Francisco", nil)
          store_member = hierarchy.createMember(
            sf_member, sf_member.getLevel.getChildLevel, "Store 14", nil)

          # Test axis contents
          assert_internal_axis_returns olap, "[Retail].[CA].Children",
            "[Retail].[CA].[Alameda]\n" \
            "[Retail].[CA].[Beverly Hills]\n" \
            "[Retail].[CA].[Los Angeles]\n" \
            "[Retail].[CA].[San Diego]\n" \
            "[Retail].[CA].[San Francisco]"
          assert_internal_axis_returns olap, "[Retail].[CA].[Alameda].Children",
            "[Retail].[CA].[Alameda].[HQ]"
          assert_internal_axis_returns olap, "[Retail].[CA].[San Francisco].Children",
            "[Retail].[CA].[San Francisco].[Store 14]"

          member_reader = get_member_reader(hierarchy)
          member_cache = get_member_cache(member_reader)

          sf_children = get_children_from_cache(member_cache, sf_member)
          assert_equal 1, sf_children.size
          alameda_children = get_children_from_cache(member_cache, alameda_member)
          assert_equal 1, alameda_children.size
          assert_equal true, store_member.getParentMember.equals(sf_member)

          # Now tell the cache that Store 14 moved to Alameda
          command = cache_control.createMoveCommand(store_member, alameda_member)
          cache_control.execute(command)

          # The list of SF children should contain 0 elements
          assert_equal 0, get_children_from_cache(member_cache, sf_member).size

          # Check Alameda's children - should have 2
          alameda_children = get_children_from_cache(member_cache, alameda_member)
          assert_equal 2, alameda_children.size

          # Test axis contents
          assert_internal_axis_returns olap, "[Retail].[CA].[San Francisco].Children", ""
          assert_internal_axis_returns olap, "[Retail].[CA].[Alameda].Children",
            "[Retail].[CA].[Alameda].[HQ]\n" \
            "[Retail].[CA].[Alameda].[Store 14]"

          # Test parent object
          assert_equal true, store_member.getParentMember.equals(alameda_member)
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  # Java: MemberCacheControlTest#testMoveFailBadLevel
  it "move fails when parent is at wrong level" do
    with_properties(EnableRolapCubeMemberCache: false) do
      clear_schema_pool
      olap = create_retail_connection
      begin
        with_locus(olap) do
          cache_control = get_cache_control(olap)
          ca_cube_member = find_member(olap, "Sales", "Retail", "CA")
          ca_member = unwrap_cube_member(ca_cube_member)
          hierarchy = ca_member.getHierarchy

          sf_member = hierarchy.createMember(
            ca_member, ca_member.getLevel.getChildLevel, "San Francisco", nil)
          store_member = hierarchy.createMember(
            sf_member, sf_member.getLevel.getChildLevel, "Store 14", nil)

          # Test axis contents
          assert_internal_axis_returns olap, "[Retail].[CA].Children",
            "[Retail].[CA].[Alameda]\n" \
            "[Retail].[CA].[Beverly Hills]\n" \
            "[Retail].[CA].[Los Angeles]\n" \
            "[Retail].[CA].[San Diego]\n" \
            "[Retail].[CA].[San Francisco]"
          assert_internal_axis_returns olap, "[Retail].[CA].[San Francisco].Children",
            "[Retail].[CA].[San Francisco].[Store 14]"

          member_reader = get_member_reader(hierarchy)
          member_cache = get_member_cache(member_reader)

          sf_children = get_children_from_cache(member_cache, sf_member)
          assert_equal 1, sf_children.size
          assert_equal true, store_member.getParentMember.equals(sf_member)

          # Now tell the cache that Store 14 moved to CA (wrong level)
          command = cache_control.createMoveCommand(store_member, ca_member)
          error = assert_raises(Java::MondrianOlap::MondrianException) do
            cache_control.execute(command)
          end
          assert_equal "new parent belongs to different level than old", error.getCause.message

          # The list of SF children should still contain 1 element
          assert_equal 1, get_children_from_cache(member_cache, sf_member).size

          # Test axis contents — should not have been modified
          assert_internal_axis_returns olap, "[Retail].[CA].[San Francisco].Children",
            "[Retail].[CA].[San Francisco].[Store 14]"
          assert_internal_axis_returns olap, "[Retail].[CA].Children",
            "[Retail].[CA].[Alameda]\n" \
            "[Retail].[CA].[Beverly Hills]\n" \
            "[Retail].[CA].[Los Angeles]\n" \
            "[Retail].[CA].[San Diego]\n" \
            "[Retail].[CA].[San Francisco]"

          # Test parent object — should be the same
          assert_equal true, store_member.getParentMember.equals(sf_member)
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  # Java: MemberCacheControlTest#testAddCommandNegative
  it "negative cases for add, delete, move, and set property commands" do
    with_properties(EnableRolapCubeMemberCache: false) do
      clear_schema_pool
      olap = create_retail_connection
      begin
        with_locus(olap) do
          cache_control = get_cache_control(olap)

          # Cannot add null member
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.createAddCommand(nil)
          end
          assert_equal "cannot add null member", error.message

          alameda_cube_member = find_member(olap, "Sales", "Retail", "CA", "Alameda")
          alameda_member = unwrap_cube_member(alameda_cube_member)
          ca_member = alameda_member.getParentMember

          emp_cube_member = find_member(olap, "HR", "Employees", "Sheri Nowmer", "Michael Spence")
          emp_member = unwrap_cube_member(emp_cube_member)

          # Cannot move null member
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.createMoveCommand(nil, alameda_member)
          end
          assert_equal "cannot move null member", error.message

          # Cannot move member to null location
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.createMoveCommand(alameda_member, nil)
          end
          assert_equal "cannot move member to null location", error.message

          # Cannot delete null member
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.java_send(:createDeleteCommand, [Java::MondrianOlap::Member], nil)
          end
          assert_equal "cannot delete null member", error.message

          # Cannot set properties on null member
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.java_send(
              :createSetPropertyCommand,
              [Java::MondrianOlap::Member, java.lang.String, java.lang.Object],
              nil, "foo", 1.to_java
            )
          end
          assert_equal "cannot set properties on null member", error.message

          # Add not supported for parent-child hierarchy
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.createAddCommand(emp_member)
          end
          assert_equal "add member not supported for parent-child hierarchy", error.message

          # Move not supported for parent-child hierarchy
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.createMoveCommand(emp_member, nil)
          end
          assert_equal "move member not supported for parent-child hierarchy", error.message

          # Delete not supported for parent-child hierarchy
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.createDeleteCommand(emp_member)
          end
          assert_equal "delete member not supported for parent-child hierarchy", error.message

          # Set properties not supported for parent-child hierarchy
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.createSetPropertyCommand(emp_member, "foo", "bar")
          end
          assert_equal "set properties not supported for parent-child hierarchy", error.message

          # All members in set must belong to same level
          error = assert_raises(Java::JavaLang::IllegalArgumentException) do
            cache_control.createSetPropertyCommand(
              cache_control.createUnionSet(
                cache_control.createMemberSet(alameda_member, false),
                cache_control.createMemberSet(ca_member, false)),
              java.util.Collections.emptyMap)
          end
          assert_equal "all members in set must belong to same level", error.message
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  # Java: MemberCacheControlTest#testFlushHierarchy
  it "flushing hierarchy causes SQL to be re-executed" do
    with_properties(EnableRolapCubeMemberCache: false) do
      clear_schema_pool
      # Flush all caches first
      olap = create_retail_connection
      begin
        with_locus(olap) do
          flush_all_caches(olap)

          cache_control = get_cache_control(olap)
          sales_cube = internal_connection(olap).getSchema.lookupCube("Sales", true)

          store_dimension = sales_cube.getDimensions.find { |d| d.getName == "Store" }
          refute_nil store_dimension, "Store dimension not found"
          store_hierarchy = store_dimension.getHierarchies[0]

          store_member_set = cache_control.createMemberSet(store_hierarchy.getAllMember, true)
          store_flusher = -> { cache_control.flush(store_member_set) }

          result = execute_internal(olap,
            "select [Store].[Mexico].[Yucatan] on 0 from [Sales]")
          store_yucatan_member = result.getAxes[0].getPositions.get(0).get(0)
          store_yucatan_member_set = cache_control.createMemberSet(store_yucatan_member, true)
          store_yucatan_flusher = -> { cache_control.flush(store_yucatan_member_set) }

          # Check that <Member>.Children uses cache when applied to an 'all' member
          check_flush_hierarchy(olap, true, store_flusher) do
            assert_internal_axis_returns olap, "[Store].Children",
              "[Store].[Canada]\n[Store].[Mexico]\n[Store].[USA]"
          end

          # Check that <Member>.Children uses cache when applied to regular member
          check_flush_hierarchy(olap, true, store_flusher) do
            assert_internal_axis_returns olap, "[Store].[USA].[CA].Children",
              "[Store].[USA].[CA].[Alameda]\n" \
              "[Store].[USA].[CA].[Beverly Hills]\n" \
              "[Store].[USA].[CA].[Los Angeles]\n" \
              "[Store].[USA].[CA].[San Diego]\n" \
              "[Store].[USA].[CA].[San Francisco]"
          end

          # Flushing Yucatan should not affect California
          check_flush_hierarchy(olap, false, store_yucatan_flusher) do
            assert_internal_axis_returns olap, "[Store].[USA].[CA].Children",
              "[Store].[USA].[CA].[Alameda]\n" \
              "[Store].[USA].[CA].[Beverly Hills]\n" \
              "[Store].[USA].[CA].[Los Angeles]\n" \
              "[Store].[USA].[CA].[San Diego]\n" \
              "[Store].[USA].[CA].[San Francisco]"
          end

          # Check that <Hierarchy>.Members uses cache
          check_flush_hierarchy(olap, true, store_flusher) do
            result = execute_internal(olap,
              "WITH MEMBER [Measures].[_Expr] AS 'Count([Store].Members)' " \
              "SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]")
            cell = result.getCell([java.lang.Integer.new(0)].to_java(:int))
            assert_equal "63", cell.getFormattedValue
          end

          # Check that <Level>.Members uses cache
          check_flush_hierarchy(olap, true, store_flusher) do
            result = execute_internal(olap,
              "WITH MEMBER [Measures].[_Expr] AS 'Count([Store].[Store Name].Members)' " \
              "SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]")
            cell = result.getCell([java.lang.Integer.new(0)].to_java(:int))
            assert_equal "25", cell.getFormattedValue
          end

          # Time hierarchy with public 'all' member
          time_dimension = sales_cube.getDimensions.find { |d| d.getName == "Time" }
          refute_nil time_dimension, "Time dimension not found"
          time_hierarchy = time_dimension.getHierarchies[0]
          time_member_set = cache_control.createMemberSet(time_hierarchy.getAllMember, true)
          time_flusher = -> { cache_control.flush(time_member_set) }

          # Check that <Level>.Members uses cache for Time
          check_flush_hierarchy(olap, true, time_flusher) do
            result = execute_internal(olap,
              "WITH MEMBER [Measures].[_Expr] AS 'Count([Time].[Month].Members)' " \
              "SELECT {[Measures].[_Expr]} ON 0 FROM [Sales]")
            cell = result.getCell([java.lang.Integer.new(0)].to_java(:int))
            assert_equal "24", cell.getFormattedValue
          end

          # Check that <Member>.Children uses cache for Time
          check_flush_hierarchy(olap, true, time_flusher) do
            assert_internal_axis_returns olap, "[Time].[1997].[Q2].Children",
              "[Time].[1997].[Q2].[4]\n[Time].[1997].[Q2].[5]\n[Time].[1997].[Q2].[6]"
          end
        end
      ensure
        olap.close
        clear_schema_pool
      end
    end
  end

  private

  # Flush all caches (equivalent to CacheControlTest.flushCache).
  def flush_all_caches(olap)
    cache_control = get_cache_control(olap)
    internal_connection(olap).getSchema.getCubes.each do |cube|
      measures_region = cache_control.createMeasuresRegion(cube)
      cache_control.flush(measures_region)
    end
  end

  # Runs command three times. Between 2nd and 3rd, flushes the cache.
  # Verifies that the 3rd time causes SQL to be re-executed (if affected).
  def check_flush_hierarchy(olap, affected, flusher)
    # Run command for first time (primes the cache)
    yield

    # Second time should not require additional SQL
    sql_before = capture_sql { yield }
    assert_empty sql_before.to_a, "Expected no SQL on second run, but got: #{sql_before.to_a}"

    # Flush cache
    flusher.call

    # Third time should require SQL if affected
    sql_after = capture_sql { yield }
    if affected
      refute_empty sql_after.to_a, "Expected SQL after flush, but got none"
    end
  end
end
