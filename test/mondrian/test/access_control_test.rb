# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2003-2005 Julian Hyde
# Copyright (C) 2005-2018 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

# Java: mondrian/src/it/java/mondrian/test/AccessControlTest.java

require_relative "../../test_helper"
require_relative "../../support/access_control_helper"

java_import "mondrian.olap.Access"
java_import "mondrian.olap.Category"
java_import "mondrian.olap.DelegatingRole"
java_import "mondrian.olap.RoleImpl"

describe "Access control" do
  include AccessControlHelper

  OLAP_ID = Java::mondrian.olap.Id
  OLAP_UTIL = Java::mondrian.olap.Util
  ROLLUP_POLICY = Java::mondrian.olap.Role::RollupPolicy

  BI_SERVER_1574_ROLE1 = <<~'XML'
    <Role name="role1">
     <SchemaGrant access="none">
      <CubeGrant cube="Warehouse" access="all">
       <HierarchyGrant hierarchy="[Store Size in SQFT]" access="custom" rollupPolicy="partial">
        <MemberGrant member="[Store Size in SQFT].[20319]" access="all"/>
        <MemberGrant member="[Store Size in SQFT].[21215]" access="none"/>
       </HierarchyGrant>
       <HierarchyGrant hierarchy="[Store Type]" access="custom" rollupPolicy="partial">
        <MemberGrant member="[Store Type].[Supermarket]" access="all"/>
       </HierarchyGrant>
      </CubeGrant>
     </SchemaGrant>
    </Role>
  XML

  # Two roles with the same [Store] member grants, one with the partial and
  # one with the full rollup policy.
  TEST_1201_ROLES = <<~'XML'
    <Role name="Role1">
      <SchemaGrant access="none">
        <CubeGrant cube="Sales" access="all">
          <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="partial">
            <MemberGrant member="[Store].[USA].[WA]" access="all"/>
            <MemberGrant member="[Store].[USA].[OR]" access="all"/>
            <MemberGrant member="[Store].[USA].[CA].[San Francisco]" access="all"/>
            <MemberGrant member="[Store].[USA].[CA].[Los Angeles]" access="all"/>
            <MemberGrant member="[Store].[Mexico]" access="all"/>
            <MemberGrant member="[Store].[Mexico].[DF]" access="none"/>
            <MemberGrant member="[Store].[Canada]" access="none"/>
          </HierarchyGrant>
        </CubeGrant>
      </SchemaGrant>
    </Role>
    <Role name="Role2">
      <SchemaGrant access="none">
        <CubeGrant cube="Sales" access="all">
          <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="full">
            <MemberGrant member="[Store].[USA].[WA]" access="all"/>
            <MemberGrant member="[Store].[USA].[OR]" access="all"/>
            <MemberGrant member="[Store].[USA].[CA].[San Francisco]" access="all"/>
            <MemberGrant member="[Store].[USA].[CA].[Los Angeles]" access="all"/>
            <MemberGrant member="[Store].[Mexico]" access="all"/>
            <MemberGrant member="[Store].[Mexico].[DF]" access="none"/>
            <MemberGrant member="[Store].[Canada]" access="none"/>
          </HierarchyGrant>
        </CubeGrant>
      </SchemaGrant>
    </Role>
  XML

  CA_CHILDREN_FILTER_MDX = <<~'MDX'
    select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
      Filter( [Store].[USA].[CA].children,          [Measures].[Unit Sales]>0) ON ROWS
    from [Sales]
    where ([Time].[1997].[Q1].[2])
  MDX

  CA_CHILDREN_TOP_COUNT_MDX = <<~'MDX'
    select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
      TopCount( [Store].[USA].[CA].children, 20,            [Measures].[Unit Sales]) ON ROWS
    from [Sales]
    where ([Time].[1997].[Q1].[2])
  MDX

  after do
    close_access_control_connections
  end

  def parse_identifier(name)
    OLAP_UTIL.parseIdentifier(name)
  end

  def name_segment(name)
    OLAP_ID::NameSegment.new(name, OLAP_ID::Quoting::UNQUOTED)
  end

  def role_connection(role_defs, role)
    foodmart_connection(foodmart_schema(role_defs: role_defs), role: role)
  end

  def assert_member_access(olap, expected_access, member_name)
    connection = olap.raw_mondrian_connection
    sales_cube = connection.getSchema.lookupCube("Sales", true)
    schema_reader = sales_cube.getSchemaReader(nil).withLocus
    member = schema_reader.getMemberByUniqueName(parse_identifier(member_name), true)
    assert_equal expected_access, connection.getRole.getAccess(member), member_name
  end

  def assert_cube_access(olap, expected_access, cube_name)
    connection = olap.raw_mondrian_connection
    cube = connection.getSchema.lookupCube(cube_name, true)
    assert_equal expected_access, connection.getRole.getAccess(cube), cube_name
  end

  def lookup_hierarchy(olap, cube_name, hierarchy_name)
    cube = olap.raw_mondrian_connection.getSchema.lookupCube(cube_name, true)
    cube.getSchemaReader(nil).lookupCompound(cube, parse_identifier(hierarchy_name), true, Category::Hierarchy)
  end

  def assert_hierarchy_access(olap, expected_access, cube_name, hierarchy_name)
    hierarchy = lookup_hierarchy(olap, cube_name, hierarchy_name)
    assert_equal expected_access, olap.raw_mondrian_connection.getRole.getAccess(hierarchy), cube_name
  end

  def hierarchy_access_details(olap, cube_name, hierarchy_name)
    olap.raw_mondrian_connection.getRole.getAccessDetails(lookup_hierarchy(olap, cube_name, hierarchy_name))
  end

  # Calls various SchemaReader methods on the members returned in a result set.
  def check_query(olap, mdx)
    connection = olap.raw_mondrian_connection
    result = connection.execute(connection.parseQuery(mdx))
    schema_reader = connection.getSchemaReader.withLocus
    result.getAxes.each do |axis|
      axis.getPositions.each do |position|
        position.each do |member|
          access_controlled_parent = schema_reader.getMemberParent(member)
          assert_nil access_controlled_parent if member.getParentMember.nil?
          refute_nil schema_reader.getMemberChildren(member)
        end
      end
    end
  end

  def axis_position_count(olap, expression)
    olap.execute("select {#{expression}} on columns from Sales").raw_cell_set.getAxes.get(0).getPositions.size
  end

  # A connection with limited access to the schema. With restrict_customers,
  # the role also restricts the levels of [Customers]. This changes the default
  # member of the dimension, and all cell values are empty because there are no
  # sales data for Canada.
  def restricted_connection(restrict_customers: true)
    olap = foodmart_connection
    connection = olap.raw_mondrian_connection
    role = RoleImpl.new
    schema = connection.getSchema
    sales_cube = schema.lookupCube("Sales", true)
    schema_reader = sales_cube.getSchemaReader(nil).withLocus
    store_hierarchy = sales_cube.lookupHierarchy(name_segment("Store"), false)
    role.grant(schema, Access::ALL_DIMENSIONS)
    role.grant(sales_cube, Access::ALL)
    nation_level = OLAP_UTIL.lookupHierarchyLevel(store_hierarchy, "Store Country")
    role.grant(store_hierarchy, Access::CUSTOM, nation_level, nil, ROLLUP_POLICY::FULL)
    [
      ["[Store].[All Stores].[USA].[OR]", Access::ALL],
      ["[Store].[All Stores].[USA]", Access::CUSTOM],
      ["[Store].[All Stores].[USA].[CA].[San Francisco]", Access::ALL],
      ["[Store].[All Stores].[USA].[CA].[Los Angeles]", Access::ALL],
      ["[Store].[All Stores].[Mexico]", Access::ALL],
      ["[Store].[All Stores].[Mexico].[DF]", Access::NONE],
      ["[Store].[All Stores].[Canada]", Access::NONE]
    ].each do |member_name, access|
      role.grant(schema_reader.getMemberByUniqueName(parse_identifier(member_name), true), access)
    end
    if restrict_customers
      customers_hierarchy = sales_cube.lookupHierarchy(name_segment("Customers"), false)
      state_province_level = OLAP_UTIL.lookupHierarchyLevel(customers_hierarchy, "State Province")
      customers_city_level = OLAP_UTIL.lookupHierarchyLevel(customers_hierarchy, "City")
      role.grant(customers_hierarchy, Access::CUSTOM, state_province_level, customers_city_level, ROLLUP_POLICY::FULL)
    end
    # No access to HR cube.
    role.grant(schema.lookupCube("HR", true), Access::NONE)
    role.makeImmutable
    connection.setRole(role)
    olap
  end

  # The [Store] hierarchy has restricted access and cell values are rolled up
  # with the partial policy.
  def rollup_connection
    role_connection(<<~'XML', 'Role1')
      <Role name="Role1">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="custom">
            <DimensionGrant dimension="[Measures]" access="all"/>
            <DimensionGrant dimension="[Gender]" access="all"/>
            <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="partial">
              <MemberGrant member="[Store].[USA]" access="all"/>
              <MemberGrant member="[Store].[USA].[CA]" access="none"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
  end

  def goodman_connection(policy)
    role_connection(<<~XML, 'California manager')
      <Role name="California manager">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" rollupPolicy="#{policy.name.downcase}" access="custom">
              <MemberGrant member="[Store].[USA].[CA]" access="all"/>
              <MemberGrant member="[Store].[USA].[OR].[Portland]" access="all"/>
            </HierarchyGrant>    </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
  end

  # A role with access to one top-level employee of the HR cube, as the
  # PeopleRole class of the Java test defines it.
  def people_role(role, schema, rep_name)
    mutable_role = role.makeMutableClone
    mutable_role.grant(schema, Access::NONE)
    cube = schema.lookupCube("HR", true)
    mutable_role.grant(cube, Access::ALL)
    hierarchy = cube.lookupHierarchy(OLAP_ID::NameSegment.new("Employees"), false)
    top_level = hierarchy.getLevels[1]
    mutable_role.grant(hierarchy, Access::CUSTOM, nil, nil, ROLLUP_POLICY::FULL)
    mutable_role.grant(hierarchy.getAllMember, Access::NONE)
    members = schema.getSchemaReader.withLocus.getLevelMembers(top_level, true).select do |member|
      member.getUniqueName.include?("[#{rep_name}]")
    end
    members.each { |member| mutable_role.grant(member, Access::ALL) }
    refute_empty members
    DelegatingRole.new(mutable_role)
  end

  # Java: AccessControlTest#testSchemaReader
  it "should give a schema reader without access control" do
    olap = foodmart_connection
    connection = olap.raw_mondrian_connection
    cube = connection.getSchema.lookupCube("Sales", true)
    schema_reader = cube.getSchemaReader(connection.getRole)
    schema_reader1 = schema_reader.withoutAccessControl
    refute_nil schema_reader1
    schema_reader2 = schema_reader1.withoutAccessControl
    refute_nil schema_reader2
  end

  # Java: AccessControlTest#testGrantDimensionNone
  it "should hide a dimension with no access" do
    olap = foodmart_connection
    connection = olap.raw_mondrian_connection
    role = connection.getRole.makeMutableClone
    sales_cube = connection.getSchema.lookupCube("Sales", true)
    schema_reader = sales_cube.getSchemaReader(role)
    gender_dimension = schema_reader.lookupCompound(
      sales_cube, OLAP_ID::Segment.toList("Gender"), true, Category::Dimension
    )
    role.grant(gender_dimension, Access::NONE)
    role.makeImmutable
    connection.setRole(role)
    assert_axis_raises(olap, "[Gender].children", "MDX object '[Gender]' not found in cube 'Sales'")
  end

  # Java: AccessControlTest#testRestrictMeasures
  it "should restrict measures" do
    schema = foodmart_schema(role_defs: <<~'XML')
      <Role name="Role1">
        <SchemaGrant access="all">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Measures]" access="all">
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role><Role name="Role2">
        <SchemaGrant access="all">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Measures]" access="custom">
              <MemberGrant member="[Measures].[Unit Sales]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML

    assert_query_returns(foodmart_connection(schema, role: 'Role1'), "SELECT {[Measures].Members} ON COLUMNS FROM [SALES]",
      <<~'RESULT')
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Store Cost]}
        {[Measures].[Store Sales]}
        {[Measures].[Sales Count]}
        {[Measures].[Customer Count]}
        {[Measures].[Promotion Sales]}
        Row #0: 266,773
        Row #0: 225,627.23
        Row #0: 565,238.13
        Row #0: 86,837
        Row #0: 5,581
        Row #0: 151,211.21
      RESULT
    assert_query_returns(foodmart_connection(schema, role: 'Role2'), "SELECT {[Measures].Members} ON COLUMNS FROM [SALES]",
      <<~'RESULT')
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Row #0: 266,773
      RESULT
  end

  # MONDRIAN-2603
  # Java: AccessControlTest#testRestrictMeasuresHierarchy_InTwoRoles
  it "should restrict the measures hierarchy in two cubes of one role" do
    schema = <<~'XML'
      <Schema name="FoodMart.DimAndMeasure.Role">
       <Dimension name="WarehouseShared">
         <Hierarchy hasAll="true" primaryKey="warehouse_id">
           <Table name="warehouse"/>
           <Level name="Country" column="warehouse_country" uniqueMembers="true"/>
           <Level name="State Province" column="warehouse_state_province"
                uniqueMembers="true"/>
           <Level name="City" column="warehouse_city" uniqueMembers="false"/>
           <Level name="Warehouse Name" column="warehouse_name" uniqueMembers="true"/>
         </Hierarchy>
       </Dimension>
       <Cube name="Warehouse1">
         <Table name="inventory_fact_1997"/>
         <DimensionUsage name="WarehouseShared" source="WarehouseShared" foreignKey="warehouse_id"/>
         <Measure name="Measure1_0" column="warehouse_cost" aggregator="sum"/>
         <Measure name="Measure1_1" column="warehouse_sales" aggregator="sum"/>
         <CalculatedMember name="Calculated Measure1" dimension="Measures">
           <Formula>[Measures].[Measure1_1] / [Measures].[Measure1_0]</Formula>
           <CalculatedMemberProperty name="FORMAT_STRING" value="$#,##0.00"/>
         </CalculatedMember>
       </Cube>
       <Cube name="Warehouse2">
         <Table name="inventory_fact_1997"/>
         <DimensionUsage name="WarehouseShared" source="WarehouseShared" foreignKey="warehouse_id"/>
         <Measure name="Measure2_0" column="warehouse_cost" aggregator="sum"/>
         <Measure name="Measure2_1" column="warehouse_sales" aggregator="sum"/>
         <CalculatedMember name="Calculated Measure2" dimension="Measures">
           <Formula>[Measures].[Measure2_1] / [Measures].[Measure2_0]</Formula>
           <CalculatedMemberProperty name="FORMAT_STRING" value="$#,##0.00"/>
         </CalculatedMember>
       </Cube>
       <Role name="Administrator">
         <SchemaGrant access="none">
           <CubeGrant cube="Warehouse1" access="custom">
             <HierarchyGrant hierarchy="[WarehouseShared]" access="all">
             </HierarchyGrant>
             <HierarchyGrant hierarchy="[Measures]" access="all">
             </HierarchyGrant>
           </CubeGrant>
           <CubeGrant cube="Warehouse2" access="custom">
             <HierarchyGrant hierarchy="[WarehouseShared]" access="all">
             </HierarchyGrant>
             <HierarchyGrant hierarchy="[Measures]" access="all">
             </HierarchyGrant>
           </CubeGrant>
         </SchemaGrant>
       </Role>
      </Schema>
    XML
    olap = foodmart_connection(schema, role: 'Administrator')

    assert_query_returns(olap, "SELECT {[Measures].Members} ON COLUMNS FROM [Warehouse2]", <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Measure2_0]}
      {[Measures].[Measure2_1]}
      {[Measures].[Fact Count]}
      Row #0: 89,043.253
      Row #0: 196,770.888
      Row #0: 4,070
    RESULT

    assert_query_returns(olap, "SELECT {[Measures].Members} ON COLUMNS FROM [Warehouse1]", <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Measure1_0]}
      {[Measures].[Measure1_1]}
      {[Measures].[Fact Count]}
      Row #0: 89,043.253
      Row #0: 196,770.888
      Row #0: 4,070
    RESULT
  end

  # Java: AccessControlTest#testRestrictLevelsAnalyzer3283
  it "should restrict levels in a union with a role without grants" do
    dimensions_def = <<~'XML'
          <Dimension visible="true" foreignKey="customer_id" highCardinality="false" name="Customers">
            <Hierarchy visible="true" hasAll="true" allMemberName="All Customers" primaryKey="customer_id">
              <Table name="customer">
              </Table>
              <Level name="Country" visible="true" column="country" type="String" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
              </Level>
              <Level name="State Province" visible="true" column="state_province" type="String" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
              </Level>
              <Level name="City" visible="true" column="city" type="String" uniqueMembers="false" levelType="Regular" hideMemberIf="Never">
              </Level>
              <Level name="Name1" visible="true" column="fname" type="String" uniqueMembers="false" levelType="Regular" hideMemberIf="Never">
                <Property name="Gender" column="gender" type="String">
                </Property>
                <Property name="Marital Status" column="marital_status" type="String">
                </Property>
                <Property name="Education" column="education" type="String">
                </Property>
                <Property name="Yearly Income" column="yearly_income" type="String">
                </Property>
              </Level>
              <Level name="First Name" visible="true" column="fname" type="String" uniqueMembers="false" levelType="Regular" hideMemberIf="Never">
              </Level>
            </Hierarchy>
            <Hierarchy name="Gender" visible="true" hasAll="true" primaryKey="customer_id">
              <Table name="customer">
              </Table>
              <Level name="Gender" visible="true" column="gender" type="String" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
                <Annotations>
                  <Annotation name="AnalyzerBusinessGroup">
                    <![CDATA[Customers]]>
                  </Annotation>
                </Annotations>
              </Level>
            </Hierarchy>
            <Hierarchy name="Marital Status" visible="true" hasAll="true" primaryKey="customer_id">
              <Table name="customer">
              </Table>
              <Level name="Marital Status" visible="true" column="marital_status" type="String" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
                <Annotations>
                  <Annotation name="AnalyzerBusinessGroup">
                    <![CDATA[Customers]]>
                  </Annotation>
                </Annotations>
              </Level>
            </Hierarchy>
          </Dimension>
        <Dimension visible="true" highCardinality="false" name="Store" foreignKey="store_id">
          <Hierarchy visible="true" hasAll="true" primaryKey="store_id">
            <Table name="store">
            </Table>
            <Level name="Store ID" visible="true" column="store_id" type="String" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
            </Level>
            <Level name="Store Country" visible="true" column="store_country" type="String" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
            </Level>
            <Level name="Store State" visible="true" column="store_state" type="String" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
            </Level>
            <Level name="Store City" visible="true" column="store_city" type="String" uniqueMembers="false" levelType="Regular" hideMemberIf="Never">
            </Level>
            <Level name="Store Name" visible="true" column="store_name" type="String" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
              <Property name="Store Type" column="store_type" type="String">
              </Property>
              <Property name="Store Manager" column="store_manager" type="String">
              </Property>
              <Property name="Store Sqft" column="store_sqft" type="Numeric">
              </Property>
              <Property name="Grocery Sqft" column="grocery_sqft" type="Numeric">
              </Property>
              <Property name="Frozen Sqft" column="frozen_sqft" type="Numeric">
              </Property>
              <Property name="Meat Sqft" column="meat_sqft" type="Numeric">
              </Property>
              <Property name="Has coffee bar" column="coffee_bar" type="Boolean">
              </Property>
              <Property name="Street address" column="store_street_address" type="String">
              </Property>
            </Level>
          </Hierarchy>
        </Dimension>
    XML
    cube_def = %(<Cube name="Sales1">  <Table name="sales_fact_1997"/>\n#{dimensions_def}</Cube>)
    # The Java test inserts the cube at the place of the virtual cube definitions.
    schema = foodmart_schema(virtual_cube_defs: cube_def, role_defs: <<~XML)
      <Role name="MR">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales1" access="all">
            <HierarchyGrant hierarchy="[Store]" access="all">
            </HierarchyGrant>
            <HierarchyGrant hierarchy="[Customers]" access="custom" topLevel="[Customers].[State Province]" bottomLevel="[Customers].[City]">
      \t  </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
      <Role name="DBPentUsers">
         <SchemaGrant access="none">
         </SchemaGrant>
      </Role>
    XML
    olap = foodmart_connection(schema, role: 'MR,DBPentUsers')

    hierarchy_access = hierarchy_access_details(olap, "Sales1", "[Customers]")

    assert_equal 2, hierarchy_access.getTopLevelDepth
    assert_equal 3, hierarchy_access.getBottomLevelDepth
  end

  # Java: AccessControlTest#testRoleMemberAccessNonExistentMemberFails
  it "should fail when a role grants access to a member that does not exist" do
    assert_error_chain_includes("Member '[Store].[USA].[Non Existent]' not found") do
      role_connection(<<~'XML', 'Role1').execute("select {[Store].Children} on 0 from [Sales]")
        <Role name="Role1">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="partial">
                <MemberGrant member="[Store].[USA].[Non Existent]" access="all"/>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML
    end
  end

  # Java: AccessControlTest#testRoleMemberAccess
  it "should give the member access of a role" do
    olap = restricted_connection
    # because CA has access
    assert_member_access(olap, Access::CUSTOM, "[Store].[USA]")
    assert_member_access(olap, Access::CUSTOM, "[Store].[Mexico]")
    assert_member_access(olap, Access::NONE, "[Store].[Mexico].[DF]")
    assert_member_access(olap, Access::NONE, "[Store].[Mexico].[DF].[Mexico City]")
    assert_member_access(olap, Access::NONE, "[Store].[Canada]")
    assert_member_access(olap, Access::NONE, "[Store].[Canada].[BC].[Vancouver]")
    assert_member_access(olap, Access::ALL, "[Store].[USA].[CA].[Los Angeles]")
    assert_member_access(olap, Access::NONE, "[Store].[USA].[CA].[San Diego]")
    # USA deny supercedes OR grant
    assert_member_access(olap, Access::NONE, "[Store].[USA].[OR].[Portland]")
    assert_member_access(olap, Access::NONE, "[Store].[USA].[WA].[Seattle]")
    assert_member_access(olap, Access::NONE, "[Store].[USA].[WA]")
    # above top level
    assert_member_access(olap, Access::NONE, "[Store].[All Stores]")
  end

  # Java: AccessControlTest#testGrantHierarchy1a
  it "should return the accessible level members" do
    # Mexico is explicitly granted, Canada is explicitly denied, and USA is
    # the parent of the allowed member San Francisco.
    assert_axis_returns(restricted_connection, "[Store].level.members", "[Store].[Mexico]\n" + "[Store].[USA]")
  end

  # Java: AccessControlTest#testGrantHierarchy1aAllMembers
  it "should return the accessible level members with allmembers" do
    assert_axis_returns(restricted_connection, "[Store].level.allmembers", "[Store].[Mexico]\n" + "[Store].[USA]")
  end

  # Java: AccessControlTest#testGrantHierarchy1b
  it "should use the first accessible member as the default member" do
    # Mexico is explicitly granted, and it is the first accessible member.
    assert_axis_returns(restricted_connection, "[Store].defaultMember", "[Store].[Mexico]")
  end

  # Java: AccessControlTest#testGrantHierarchy1c
  it "should use the first member of the top level as the default member" do
    # the root element is All Customers
    assert_axis_returns(restricted_connection, "[Customers].defaultMember", "[Customers].[Canada].[BC]")
  end

  # Java: AccessControlTest#testGrantHierarchy2
  it "should return the parent of an allowed member" do
    # California is the parent of an allowed member.
    olap = restricted_connection
    assert_axis_returns(olap, "[Store].[USA].children", "[Store].[USA].[CA]")
    assert_axis_returns(olap, "[Store].[USA].children", "[Store].[USA].[CA]")
    assert_axis_returns(olap, "[Store].[USA].[CA].children", <<~'AXIS')
      [Store].[USA].[CA].[Los Angeles]
      [Store].[USA].[CA].[San Francisco]
    AXIS
  end

  # Java: AccessControlTest#testGrantHierarchy3
  it "should not find a child of a denied member" do
    # Washington is a child of a denied member.
    assert_axis_raises(restricted_connection, "[Store].[USA].[WA]", "not found")
  end

  # Java: AccessControlTest#testGrantHierarchy4
  it "should apply the member grants in order" do
    # Oregon is not accessible: the order of the grants matters.
    assert_axis_raises(restricted_connection, "[Store].[USA].[OR].children", "not found")
  end

  # Java: AccessControlTest#testGrantHierarchy5
  it "should not find a member above the top level" do
    olap = restricted_connection
    assert_axis_raises(olap, "[Store].[All Stores]", "not found")
    # no: [All Stores] -- above top level
    # no: [Canada] -- not explicitly allowed
    # yes: [Mexico] -- explicitly allowed -- and all its children except [DF]
    # no: [Mexico].[DF]
    # yes: [USA] -- implicitly allowed
    # yes: [CA] -- implicitly allowed
    # no: [OR], [WA]
    # yes: [San Francisco] -- explicitly allowed
    # no: [San Diego]
    assert_axis_returns(olap, "[Store].members", <<~'AXIS')
      [Store].[Mexico]
      [Store].[Mexico].[Guerrero]
      [Store].[Mexico].[Guerrero].[Acapulco]
      [Store].[Mexico].[Guerrero].[Acapulco].[Store 1]
      [Store].[Mexico].[Jalisco]
      [Store].[Mexico].[Jalisco].[Guadalajara]
      [Store].[Mexico].[Jalisco].[Guadalajara].[Store 5]
      [Store].[Mexico].[Veracruz]
      [Store].[Mexico].[Veracruz].[Orizaba]
      [Store].[Mexico].[Veracruz].[Orizaba].[Store 10]
      [Store].[Mexico].[Yucatan]
      [Store].[Mexico].[Yucatan].[Merida]
      [Store].[Mexico].[Yucatan].[Merida].[Store 8]
      [Store].[Mexico].[Zacatecas]
      [Store].[Mexico].[Zacatecas].[Camacho]
      [Store].[Mexico].[Zacatecas].[Camacho].[Store 4]
      [Store].[Mexico].[Zacatecas].[Hidalgo]
      [Store].[Mexico].[Zacatecas].[Hidalgo].[Store 12]
      [Store].[Mexico].[Zacatecas].[Hidalgo].[Store 18]
      [Store].[USA]
      [Store].[USA].[CA]
      [Store].[USA].[CA].[Los Angeles]
      [Store].[USA].[CA].[Los Angeles].[Store 7]
      [Store].[USA].[CA].[San Francisco]
      [Store].[USA].[CA].[San Francisco].[Store 14]
    AXIS
  end

  # Java: AccessControlTest#testGrantHierarchy6
  it "should give no parent at the top level" do
    assert_axis_returns(restricted_connection, "[Customers].[USA].[CA].parent", "")
  end

  # Java: AccessControlTest#testGrantHierarchy7
  it "should not find members above the top level" do
    assert_axis_raises(restricted_connection, "[Customers].[Canada].children",
      "MDX object '[Customers].[Canada]' not found in cube 'Sales'")
  end

  # Java: AccessControlTest#testGrantHierarchy8
  it "should not find members below the bottom level" do
    # Catherine Abel in San Francisco is below the bottom level.
    olap = restricted_connection
    assert_axis_raises(olap, "[Customers].[USA].[CA].[San Francisco].[Catherine Abel]", "not found")
    assert_axis_returns(olap, "[Customers].[USA].[CA].[San Francisco].children", "")
    # 13 states, 109 cities
    assert_equal 122, axis_position_count(olap, "[Customers].members")
  end

  # Java: AccessControlTest#testGrantHierarchy8AllMembers
  it "should not find members below the bottom level with allmembers" do
    olap = restricted_connection
    assert_axis_raises(olap, "[Customers].[USA].[CA].[San Francisco].[Catherine Abel]", "not found")
    assert_axis_returns(olap, "[Customers].[USA].[CA].[San Francisco].children", "")
    # 13 states, 109 cities
    assert_equal 122, axis_position_count(olap, "[Customers].allmembers")
  end

  # MONDRIAN-1201: native rollups did not handle access control with more
  # than one member with access="all".
  # Java: AccessControlTest#testBugMondrian_1201_MultipleMembersInRoleAccessControl
  it "should apply a role with many member grants in native evaluation" do
    partial_rollup = role_connection(TEST_1201_ROLES, 'Role1')
    full_rollup = role_connection(TEST_1201_ROLES, 'Role2')

    # Must return only 2 [USA].[CA] stores
    assert_query_returns(partial_rollup, CA_CHILDREN_FILTER_MDX, <<~'RESULT')
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Francisco]}
      Row #0: 2,614
      Row #1: 187
    RESULT

    # Must return only 2 [USA].[CA] stores
    assert_query_returns(partial_rollup, CA_CHILDREN_TOP_COUNT_MDX, <<~'RESULT')
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Francisco]}
      Row #0: 2,614
      Row #1: 187
    RESULT

    state_filter_mdx = <<~'MDX'
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        Filter( [Store].[Store State].Members,          [Measures].[Unit Sales]>4000) ON ROWS
      from [Sales]
      where ([Time].[1997].[Q1].[2])
    MDX

    # Partial Rollup: [USA].[CA] rolls up only up to 2.801
    assert_query_returns(partial_rollup, state_filter_mdx, <<~'RESULT')
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[OR]}
      {[Store].[USA].[WA]}
      Row #0: 4,617
      Row #1: 10,319
    RESULT

    # Full Rollup: [USA].[CA] rolls up to 6.021
    assert_query_returns(full_rollup, state_filter_mdx, <<~'RESULT')
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA]}
      {[Store].[USA].[OR]}
      {[Store].[USA].[WA]}
      Row #0: 6,021
      Row #1: 4,617
      Row #2: 10,319
    RESULT
  end

  # Java: AccessControlTest#testBugMondrian_2586_RaggedDimMembersShouldBeVisible
  it "should show the members of a ragged dimension" do
    ragged_sales = role_connection(<<~'XML', 'Sales Ragged')
      <Role name="Sales Ragged">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales Ragged" access="all" />
        </SchemaGrant>
      </Role>
    XML
    assert_query_returns(ragged_sales,
      "select {[Measures].[Unit Sales]} ON COLUMNS, {[Geography].[Country].MEMBERS} ON ROWS from [Sales Ragged]",
      <<~'RESULT')
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Geography].[Canada]}
        {[Geography].[Israel]}
        {[Geography].[Mexico]}
        {[Geography].[USA]}
        {[Geography].[Vatican]}
        Row #0:
        Row #1: 13,694
        Row #2:
        Row #3: 217,822
        Row #4: 35,257
      RESULT
  end

  # Java: AccessControlTest#testBugMondrian_1201_CacheAwareOfRoleAccessControl
  it "should not share the cache between roles with different member grants" do
    roles = <<~'XML'
      <Role name="Role1">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="partial">
              <MemberGrant member="[Store].[USA].[WA]" access="all"/>
              <MemberGrant member="[Store].[USA].[OR]" access="all"/>
              <MemberGrant member="[Store].[USA].[CA].[San Francisco]" access="all"/>
              <MemberGrant member="[Store].[USA].[CA].[Los Angeles]" access="all"/>
              <MemberGrant member="[Store].[Mexico]" access="all"/>
              <MemberGrant member="[Store].[Mexico].[DF]" access="none"/>
              <MemberGrant member="[Store].[Canada]" access="none"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
      <Role name="Role2">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="partial">
              <MemberGrant member="[Store].[USA].[WA]" access="all"/>
              <MemberGrant member="[Store].[USA].[OR]" access="all"/>
              <MemberGrant member="[Store].[USA].[CA].[San Francisco]" access="all"/>
              <MemberGrant member="[Store].[Mexico]" access="all"/>
              <MemberGrant member="[Store].[Mexico].[DF]" access="none"/>
              <MemberGrant member="[Store].[Canada]" access="none"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML

    # Put query into cache
    assert_query_returns(role_connection(roles, 'Role1'), CA_CHILDREN_FILTER_MDX, <<~'RESULT')
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Francisco]}
      Row #0: 2,614
      Row #1: 187
    RESULT

    # Run same query using another role with different access controls
    assert_query_returns(role_connection(roles, 'Role2'), CA_CHILDREN_TOP_COUNT_MDX, <<~'RESULT')
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA].[San Francisco]}
      Row #0: 187
    RESULT
  end

  # MONDRIAN-1127: native TopCount did not apply the user roles.
  # Java: AccessControlTest#testBugMondrian1127OneSlicerOnly
  it "should apply the role in a native TopCount with one slicer member" do
    assert_query_returns(restricted_connection, <<~'MDX', <<~'RESULT')
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        TopCount([Store].[USA].[CA].Children, 10,           [Measures].[Unit Sales]) ON ROWS
      from [Sales]
      where ([Time].[1997].[Q1].[2])
    MDX
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Francisco]}
      Row #0: 2,614
      Row #1: 187
    RESULT

    assert_query_returns(foodmart_connection, <<~'MDX', <<~'RESULT')
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        NON EMPTY TopCount([Store].[USA].[CA].Children, 10,            [Measures].[Unit Sales]) ON ROWS
      from [Sales]
      where ([Time].[1997].[Q1].[2])
    MDX
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Diego]}
      {[Store].[USA].[CA].[Beverly Hills]}
      {[Store].[USA].[CA].[San Francisco]}
      Row #0: 2,614
      Row #1: 1,879
      Row #2: 1,341
      Row #3: 187
    RESULT
  end

  # Java: AccessControlTest#testBugMondrian1127MultipleSlicers
  it "should apply the role in a native TopCount with many slicer members" do
    assert_query_returns(restricted_connection, <<~'MDX', <<~'RESULT')
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        TopCount([Store].[USA].[CA].Children, 10,           [Measures].[Unit Sales]) ON ROWS
      from [Sales]
      where ([Time].[1997].[Q1].[2] : [Time].[1997].[Q1].[3])
    MDX
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      {[Time].[1997].[Q1].[3]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Francisco]}
      Row #0: 4,497
      Row #1: 337
    RESULT

    assert_query_returns(foodmart_connection, <<~'MDX', <<~'RESULT')
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        NON EMPTY TopCount([Store].[USA].[CA].Children, 10,            [Measures].[Unit Sales]) ON ROWS
      from [Sales]
      where ([Time].[1997].[Q1].[2] : [Time].[1997].[Q1].[3])
    MDX
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      {[Time].[1997].[Q1].[3]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Diego]}
      {[Store].[USA].[CA].[Beverly Hills]}
      {[Store].[USA].[CA].[San Francisco]}
      Row #0: 4,497
      Row #1: 4,094
      Row #2: 2,585
      Row #3: 337
    RESULT
  end

  # Aggregate is only over SF and LA, also when a function calls it.
  # Java: AccessControlTest#testGrantHierarchy9
  it "should aggregate only the accessible members in a function" do
    # Analysis services doesn't allow aggregation within calculated
    # measures, so use the following query to generate the results:
    #
    #   with member [Store].[SF LA] as
    #     'Aggregate({[USA].[CA].[San Francisco], [Store].[USA].[CA].[Los
    #     Angeles]})'
    #   select {[Measures].[Unit Sales]} on columns,
    #    {[Gender].children} on rows
    #   from Sales
    #   where ([Marital Status].[S], [Store].[SF LA])
    assert_query_returns(restricted_connection(restrict_customers: false), <<~'MDX', <<~'RESULT')
      with member [Measures].[California Unit Sales] as  'Aggregate({[Store].[USA].[CA].children}, [Measures].[Unit Sales])'
      select {[Measures].[California Unit Sales]} on columns,
       {[Gender].children} on rows
      from Sales
      where ([Marital Status].[S])
    MDX
      Axis #0:
      {[Marital Status].[S]}
      Axis #1:
      {[Measures].[California Unit Sales]}
      Axis #2:
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 6,636
      Row #1: 7,329
    RESULT
  end

  # Java: AccessControlTest#testGrantHierarchyA
  it "should include the missing cells in the totals" do
    # totals for USA include missing cells
    assert_query_returns(restricted_connection(restrict_customers: false), <<~'MDX', <<~'RESULT')
      select {[Unit Sales]} on columns,
      {[Store].[USA], [Store].[USA].children} on rows
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA]}
      {[Store].[USA].[CA]}
      Row #0: 266,773
      Row #1: 74,748
    RESULT
  end

  # Java: AccessControlTest#_testSharedObjectsInGrantMappingsBug
  it "should not share objects in the grant mappings" do
    skip "Disabled in the Java test"
    olap = foodmart_connection
    connection = olap.raw_mondrian_connection
    schema = connection.getSchema
    sales_cube = schema.lookupCube("Sales", true)
    warehouse_cube = schema.lookupCube("Warehouse", true)
    measures_in_sales = sales_cube.lookupHierarchy(name_segment("Measures"), false)
    store_in_warehouse = warehouse_cube.lookupHierarchy(name_segment("Store"), false)

    role = RoleImpl.new
    role.grant(schema, Access::NONE)
    role.grant(sales_cube, Access::NONE)
    # For using hierarchy Measures in assert_expression_raises
    role.grant(measures_in_sales, Access::ALL, nil, nil, ROLLUP_POLICY::FULL)
    role.grant(warehouse_cube, Access::NONE)
    role.grant(store_in_warehouse.getDimension, Access::ALL)
    role.makeImmutable
    connection.setRole(role)
    # Looking up default member on dimension Store in cube Sales should fail.
    assert_expression_raises(olap, "[Store].DefaultMember", "'[Store]' not found in cube 'Sales'")
  end

  # Java: AccessControlTest#testNoAccessToCube
  it "should not find a cube with no access" do
    assert_query_raises(restricted_connection(restrict_customers: false), "select from [HR]", "MDX cube 'HR' not found")
  end

  # Partial rollup policy: [USA] = [OR] + [WA], not the usual [CA] + [OR] + [WA].
  # Java: AccessControlTest#testRollupPolicyBasic
  it "should apply the partial rollup policy" do
    assert_query_returns(rollup_connection, "select {[Store].[USA], [Store].[USA].Children} on 0\nfrom [Sales]",
      <<~'RESULT')
        Axis #0:
        {}
        Axis #1:
        {[Store].[USA]}
        {[Store].[USA].[OR]}
        {[Store].[USA].[WA]}
        Row #0: 192,025
        Row #0: 67,659
        Row #0: 124,366
      RESULT
  end

  # The total for [Store].[All Stores] is similarly reduced. All children of
  # [All Stores] are visible, but one grandchild is not. Normally the total is
  # 266,773.
  # Java: AccessControlTest#testRollupPolicyAll
  it "should apply the partial rollup policy to the all member" do
    assert_expression_returns(rollup_connection, "([Store].[All Stores])", "192,025")
  end

  # [Store].[All Stores] is the default member of the [Stores] hierarchy.
  # Java: AccessControlTest#testRollupPolicyAllAsDefault
  it "should apply the partial rollup policy to the default member" do
    assert_expression_returns(rollup_connection, "([Store])", "192,025")
  end

  # The Parent relationship does not go around the access control.
  # Java: AccessControlTest#testRollupPolicyAllAsParent
  it "should apply the partial rollup policy to the parent member" do
    assert_expression_returns(rollup_connection, "([Store].[USA].Parent)", "192,025")
  end

  # MONDRIAN-1283: Mondrian doesn't restrict dimension members when the
  # dimension isn't included.
  # Java: AccessControlTest#testUnusedAccessControlledDimension
  it "should apply an access-controlled dimension that the query does not use" do
    assert_query_returns(rollup_connection, "select [Gender].Children on 0 from [Sales]", <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 94,799
      Row #0: 97,226
    RESULT
    assert_query_returns(foodmart_connection, "select [Gender].Children on 0 from [Sales]", <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 131,558
      Row #0: 135,215
    RESULT
  end

  # Members below the bottom level are regarded as visible.
  # Java: AccessControlTest#testRollupBottomLevel
  it "should include the members below the bottom level in the rollup" do
    [
      [ROLLUP_POLICY::FULL, "74,748", "36,759", "266,773"],
      [ROLLUP_POLICY::PARTIAL, "72,739", "35,775", "264,764"],
      [ROLLUP_POLICY::HIDDEN, "", "", ""]
    ].each do |rollup_policy, v1, v2, v3|
      olap = role_connection(<<~XML, 'Role1')
        <Role name="Role1">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="#{rollup_policy}" bottomLevel="[Customers].[City]">
                <MemberGrant member="[Customers].[USA]" access="all"/>
                <MemberGrant member="[Customers].[USA].[CA]" access="all"/>
                <MemberGrant member="[Customers].[USA].[CA].[Los Angeles]" access="none"/>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML
      # All of the children of [San Francisco] are invisible, because [City]
      # is the bottom level, but that shouldn't affect the total.
      assert_expression_returns(olap, "([Customers].[USA].[CA].[San Francisco])", "88")
      assert_expression_raises(olap, "([Customers].[USA].[CA].[Los Angeles])",
        "MDX object '[Customers].[USA].[CA].[Los Angeles]' not found in cube 'Sales'")

      assert_expression_returns(olap, "([Customers].[USA].[CA])", v1)
      assert_expression_returns(olap, "([Customers].[USA].[CA], [Gender].[F])", v2)
      assert_expression_returns(olap, "([Customers].[USA])", v3)

      check_query(olap, "select [Customers].Children on 0, [Gender].Members on 1 from [Sales]")
    end
  end

  # Java: AccessControlTest#testRollupPolicyNegative
  it "should fail with a bad rollup policy value" do
    assert_error_chain_includes("Illegal rollupPolicy value 'bad'") do
      role_connection(<<~'XML', 'Role1').execute("select from [Sales]")
        <Role name="Role1">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="bad" bottomLevel="[Customers].[City]">
                <MemberGrant member="[Customers].[USA]" access="all"/>
                <MemberGrant member="[Customers].[USA].[CA].[Los Angeles]" access="none"/>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML
    end
  end

  # All children are visible but a grandchild is not.
  # Java: AccessControlTest#testRollupPolicyGreatGrandchildInvisible
  it "should apply the rollup policy when a great-grandchild is not visible" do
    [
      [ROLLUP_POLICY::FULL, "266,773", "74,748"],
      [ROLLUP_POLICY::PARTIAL, "266,767", "74,742"],
      [ROLLUP_POLICY::HIDDEN, "", ""]
    ].each do |policy, v1, v2|
      olap = role_connection(<<~XML, 'Role1')
        <Role name="Role1">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="#{policy}">
                <MemberGrant member="[Customers].[USA]" access="all"/>
                <MemberGrant member="[Customers].[USA].[CA].[San Francisco].[Gladys Evans]" access="none"/>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML
      assert_expression_returns(olap, "[Measures].[Unit Sales]", v1)
      assert_expression_returns(olap, "([Measures].[Unit Sales], [Customers].[USA])", v1)
      assert_expression_returns(olap, "([Measures].[Unit Sales], [Customers].[USA].[CA])", v2)
    end
  end

  # Two hierarchies are access-controlled at the same time.
  # Java: AccessControlTest#testRollupPolicySimultaneous
  it "should apply the rollup policy of two hierarchies at the same time" do
    # note that v2 is different for full vs partial, v3 is the same
    [
      [ROLLUP_POLICY::FULL, "266,773", "74,748", "25,635"],
      [ROLLUP_POLICY::PARTIAL, "72,631", "72,631", "25,635"],
      [ROLLUP_POLICY::HIDDEN, "", "", ""]
    ].each do |policy, v1, v2, v3|
      olap = role_connection(<<~XML, 'Role1')
        <Role name="Role1">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="#{policy}">
                <MemberGrant member="[Customers].[USA]" access="all"/>
                <MemberGrant member="[Customers].[USA].[CA].[San Francisco].[Gladys Evans]" access="none"/>
              </HierarchyGrant>
              <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="#{policy}">
                <MemberGrant member="[Store].[USA].[CA]" access="all"/>
                <MemberGrant member="[Store].[USA].[CA].[San Francisco].[Store 14]" access="none"/>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML
      assert_expression_returns(olap, "[Measures].[Unit Sales]", v1)
      assert_expression_returns(olap, "([Measures].[Unit Sales], [Customers].[USA])", v1)
      assert_expression_returns(olap, "([Measures].[Unit Sales], [Customers].[USA].[CA])", v2)
      assert_expression_returns(olap, "([Measures].[Unit Sales], [Customers].[USA].[CA], [Store].[USA].[CA])", v2)
      assert_expression_returns(olap,
        "([Measures].[Unit Sales], [Customers].[USA].[CA], [Store].[USA].[CA].[San Diego])", v3)
    end
  end

  # Java: AccessControlTest#testUnionRole
  it "should combine the access of a union role" do
    schema = foodmart_schema(role_defs: <<~'XML')
      <Role name="Role1">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="Partial">
              <MemberGrant member="[Customers].[USA].[CA]" access="all"/>
              <MemberGrant member="[Customers].[USA].[CA].[San Francisco].[Gladys Evans]" access="none"/>
            </HierarchyGrant>
            <HierarchyGrant hierarchy="[Promotion Media]" access="all"/>
            <HierarchyGrant hierarchy="[Marital Status]" access="none"/>
            <HierarchyGrant hierarchy="[Gender]" access="none"/>
            <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="Partial" topLevel="[Store].[Store State]"/>
          </CubeGrant>
          <CubeGrant cube="Warehouse" access="all"/>
        </SchemaGrant>
      </Role>
      <Role name="Role2">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="none">
            <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="Hidden">
              <MemberGrant member="[Customers].[USA]" access="all"/>
              <MemberGrant member="[Customers].[USA].[CA]" access="none"/>
              <MemberGrant member="[Customers].[USA].[OR]" access="none"/>
              <MemberGrant member="[Customers].[USA].[OR].[Portland]" access="all"/>
            </HierarchyGrant>
            <HierarchyGrant hierarchy="[Store]" access="all" rollupPolicy="Hidden"/>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML

    assert_error_chain_includes("Role 'Role3' not found") { foodmart_connection(schema, role: 'Role3,Role2') }
    assert_error_chain_includes("Role 'Role3' not found") { foodmart_connection(schema, role: 'Role1,Role3') }

    olap = foodmart_connection(schema, role: 'Role1,Role2')

    # Cube access:
    # Both can see [Sales]
    # Role1 only see [Warehouse]
    # Neither can see [Warehouse and Sales]
    assert_cube_access(olap, Access::ALL, "Sales")
    assert_cube_access(olap, Access::ALL, "Warehouse")
    assert_cube_access(olap, Access::NONE, "Warehouse and Sales")

    # Hierarchy access:
    # Both can see [Customers] with Custom access
    # Both can see [Store], Role1 with Custom access, Role2 with All access
    # Role1 can see [Promotion Media], Role2 cannot
    # Neither can see [Marital Status]
    assert_hierarchy_access(olap, Access::CUSTOM, "Sales", "[Customers]")
    assert_hierarchy_access(olap, Access::ALL, "Sales", "[Store]")
    assert_hierarchy_access(olap, Access::ALL, "Sales", "[Promotion Media]")
    assert_hierarchy_access(olap, Access::NONE, "Sales", "[Marital Status]")

    # Rollup policy is the greater of Role1's partian and Role2's hidden
    hierarchy_access = hierarchy_access_details(olap, "Sales", "[Store]")
    assert_equal ROLLUP_POLICY::PARTIAL, hierarchy_access.getRollupPolicy
    # One of the roles is restricting the levels, so we
    # expect only the levels from 2 to 4 to be available.
    assert_equal 2, hierarchy_access.getTopLevelDepth
    assert_equal 4, hierarchy_access.getBottomLevelDepth

    # Member access:
    # both can see [USA]
    assert_member_access(olap, Access::CUSTOM, "[Customers].[USA]")
    # Role1 can see [CA], Role2 cannot
    assert_member_access(olap, Access::CUSTOM, "[Customers].[USA].[CA]")
    # Role1 cannoy see [USA].[OR].[Portland], Role2 can
    assert_member_access(olap, Access::ALL, "[Customers].[USA].[OR].[Portland]")
    # Role1 cannot see [USA].[OR], Role2 can see it by virtue of [Portland]
    assert_member_access(olap, Access::CUSTOM, "[Customers].[USA].[OR]")
    # Neither can see Beaverton
    assert_member_access(olap, Access::NONE, "[Customers].[USA].[OR].[Beaverton]")

    # Rollup policy
    mdx = <<~'MDX'
      select Hierarchize(
      {[Customers].[USA].Children,
       [Customers].[USA].[OR].Children}) on 0
      from [Sales]
    MDX
    assert_query_returns(foodmart_connection(schema), mdx, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Customers].[USA].[CA]}
      {[Customers].[USA].[OR]}
      {[Customers].[USA].[OR].[Albany]}
      {[Customers].[USA].[OR].[Beaverton]}
      {[Customers].[USA].[OR].[Corvallis]}
      {[Customers].[USA].[OR].[Lake Oswego]}
      {[Customers].[USA].[OR].[Lebanon]}
      {[Customers].[USA].[OR].[Milwaukie]}
      {[Customers].[USA].[OR].[Oregon City]}
      {[Customers].[USA].[OR].[Portland]}
      {[Customers].[USA].[OR].[Salem]}
      {[Customers].[USA].[OR].[W. Linn]}
      {[Customers].[USA].[OR].[Woodburn]}
      {[Customers].[USA].[WA]}
      Row #0: 74,748
      Row #0: 67,659
      Row #0: 6,806
      Row #0: 4,558
      Row #0: 9,539
      Row #0: 4,910
      Row #0: 9,596
      Row #0: 5,145
      Row #0: 3,708
      Row #0: 3,583
      Row #0: 7,678
      Row #0: 4,175
      Row #0: 7,961
      Row #0: 124,366
    RESULT

    assert_query_raises(foodmart_connection(schema, role: 'Role1'), mdx,
      "MDX object '[Customers].[USA].[OR]' not found in cube 'Sales'")

    assert_query_raises(foodmart_connection(schema, role: 'Role2'), mdx, "MDX cube 'Sales' not found")

    # Compared to above:
    # a. cities in Oregon are missing besides Portland
    # b. total for Oregon = total for Portland
    assert_query_returns(olap, mdx, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Customers].[USA].[CA]}
      {[Customers].[USA].[OR]}
      {[Customers].[USA].[OR].[Portland]}
      {[Customers].[USA].[WA]}
      Row #0: 74,742
      Row #0: 3,583
      Row #0: 3,583
      Row #0: 124,366
    RESULT
    check_query(olap, mdx)
  end

  # Java: AccessControlTest#testUnionOfUnionRole
  it "should combine the access of a union of a union role" do
    role_defs = <<~'XML'
      <Role name="USA manager">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <DimensionGrant access="all" dimension="[Measures]"/>
            <HierarchyGrant access="custom" hierarchy="[Customers]">
              <MemberGrant access="all" member="[Customers].[USA]"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
      <Role name="parent of USA manager">
        <Union>
          <RoleUsage roleName="USA manager"/>
        </Union>
      </Role><Role name="grandparent of USA manager">
        <Union>
          <RoleUsage roleName="parent of USA manager"/>
        </Union>
      </Role>
    XML
    olap = role_connection(role_defs, 'grandparent of USA manager')

    # Can access [Sales]?
    assert_cube_access(olap, Access::ALL, "Sales")

    # Has custom access to [Customers]?
    assert_hierarchy_access(olap, Access::CUSTOM, "Sales", "[Customers]")

    hierarchy_access = hierarchy_access_details(olap, "Sales", "[Customers]")

    # Can access all levels of the [Customers] hierarchy?
    assert_equal 0, hierarchy_access.getTopLevelDepth
    assert_equal 4, hierarchy_access.getBottomLevelDepth

    # Can see [USA]?
    assert_member_access(olap, Access::ALL, "[Customers].[USA]")

    # Cannot see [Mexico]?
    assert_member_access(olap, Access::NONE, "[Customers].[Mexico]")
  end

  # MONDRIAN-1384
  # Java: AccessControlTest#testUnionRoleHasInaccessibleDescendants
  it "should find inaccessible descendants in a union role" do
    olap = role_connection(<<~'XML', 'Role1,Role2')
      <Role name="Role1">
        <SchemaGrant access="none">
        </SchemaGrant>
      </Role>
      <Role name="Role2">
        <SchemaGrant access="all">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="partial">
              <MemberGrant member="[Customers].[USA].[OR]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
    connection = olap.raw_mondrian_connection
    cube = connection.getSchema.lookupCube("Sales", true)
    access_details = connection.getRole.getAccessDetails(cube.lookupHierarchy(name_segment("Customers"), false))
    schema_reader = cube.getSchemaReader(nil).withLocus
    assert_equal true,
      access_details.hasInaccessibleDescendants(schema_reader.getMemberByUniqueName(parse_identifier("[Customers].[USA]"), true))
  end

  # MONDRIAN-1168: a union of roles sometimes returned levels which the access
  # control restricts.
  # Java: AccessControlTest#testRoleUnionWithLevelRestrictions
  it "should restrict the levels in a union role" do
    olap = role_connection(<<~'XML', 'Role1,Role2')
      <Role name="Role1">
        <SchemaGrant access="all">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="Partial" topLevel="[Customers].[State Province]" bottomLevel="[Customers].[State Province]">
              <MemberGrant member="[Customers].[USA].[CA]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
      <Role name="Role2">
        <SchemaGrant access="none">
        </SchemaGrant>
      </Role>
    XML

    assert_query_returns(olap, "select {[Customers].[State Province].Members} on columns from [Sales]", <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Customers].[USA].[CA]}
      Row #0: 74,748
    RESULT

    assert_query_returns(olap, "select {[Customers].[Country].Members} on columns from [Sales]", <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
    RESULT

    connection = olap.raw_mondrian_connection
    reader = connection.getSchemaReader.withLocus
    cube = reader.getCubes.find { |candidate_cube| candidate_cube.getName == "Sales" }
    refute_nil cube
    reader = cube.getSchemaReader(connection.getRole)
    dimension = reader.getCubeDimensions(cube).find { |candidate_dimension| candidate_dimension.getName == "Customers" }
    refute_nil dimension
    hierarchy = reader.getDimensionHierarchies(dimension).get(0)
    refute_nil hierarchy
    levels = reader.getHierarchyLevels(hierarchy)

    # Do some tests
    assert_equal 1, levels.size
    assert_equal 2, connection.getRole.getAccessDetails(hierarchy).getBottomLevelDepth
    assert_equal 2, connection.getRole.getAccessDetails(hierarchy).getTopLevelDepth
  end

  PRODUCT_DRINK_ROLE = <<~'XML'
    <Role name="Role1">
      <SchemaGrant access="none">
        <CubeGrant cube="Sales" access="all">
          <HierarchyGrant hierarchy="[Product]" access="custom">
            <MemberGrant member="[Product].[Drink]" access="all"/>
          </HierarchyGrant>
        </CubeGrant>
      </SchemaGrant>
    </Role>
  XML

  PRODUCT_DRINK_RESULT = <<~'RESULT'
    Axis #0:
    {}
    Axis #1:
    {[Measures].[Unit Sales]}
    Axis #2:
    {[Gender].[All Gender], [Product].[Drink]}
    Row #0: 24,597
  RESULT

  # MONDRIAN-369: Non Empty Crossjoin fails to enforce role access.
  # Java: AccessControlTest#testNonEmptyAccess
  it "should apply the role in a non empty crossjoin" do
    olap = role_connection(PRODUCT_DRINK_ROLE, 'Role1')

    # regular crossjoin returns the correct list of product children
    mdx = "select {[Measures].[Unit Sales]} ON COLUMNS,  Crossjoin({[Gender].[All Gender]}, " \
      "[Product].Children) ON ROWS from [Sales]"
    assert_query_returns(olap, mdx, PRODUCT_DRINK_RESULT)
    check_query(olap, mdx)

    # with bug MONDRIAN-397, non empty crossjoin did not return the correct
    # list
    mdx2 = "select {[Measures].[Unit Sales]} ON COLUMNS, NON EMPTY Crossjoin({[Gender].[All Gender]}, " \
      "[Product].[All Products].Children) ON ROWS from [Sales]"
    assert_query_returns(olap, mdx2, PRODUCT_DRINK_RESULT)
    check_query(olap, mdx2)
  end

  # Java: AccessControlTest#testNonEmptyAccessLevelMembers
  it "should apply the role to level members in a non empty crossjoin" do
    olap = role_connection(PRODUCT_DRINK_ROLE, 'Role1')

    # <Level>.members inside regular crossjoin returns the correct list of
    # product members
    mdx = "select {[Measures].[Unit Sales]} ON COLUMNS,  Crossjoin({[Gender].[All Gender]}, " \
      "[Product].[Product Family].Members) ON ROWS from [Sales]"
    assert_query_returns(olap, mdx, PRODUCT_DRINK_RESULT)
    check_query(olap, mdx)

    # with bug MONDRIAN-397, <Level>.members inside non empty crossjoin did
    # not return the correct list
    mdx2 = "select {[Measures].[Unit Sales]} ON COLUMNS, NON EMPTY Crossjoin({[Gender].[All Gender]}, " \
      "[Product].[Product Family].Members) ON ROWS from [Sales]"
    assert_query_returns(olap, mdx2, PRODUCT_DRINK_RESULT)
    check_query(olap, mdx2)
  end

  # MONDRIAN-406: rollup policy doesn't work for members that are implicitly
  # visible.
  # Java: AccessControlTest#testGoodman
  it "should apply the rollup policy to implicitly visible members" do
    query = <<~'MDX'
      select {[Measures].[Unit Sales]} ON COLUMNS,
      Hierarchize(Union(Union(Union({[Store].[All Stores]}, [Store].[All Stores].Children), [Store].[All Stores].[USA].Children), [Store].[All Stores].[USA].[CA].Children)) ON ROWS
      from [Sales]
      where [Time].[1997]
    MDX

    # Note that total for [Store].[All Stores] and [Store].[USA] is sum
    # of visible children [Store].[CA] and [Store].[OR].[Portland].
    olap = goodman_connection(ROLLUP_POLICY::PARTIAL)
    assert_query_returns(olap, query, <<~'RESULT')
      Axis #0:
      {[Time].[1997]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[All Stores]}
      {[Store].[USA]}
      {[Store].[USA].[CA]}
      {[Store].[USA].[CA].[Alameda]}
      {[Store].[USA].[CA].[Beverly Hills]}
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Diego]}
      {[Store].[USA].[CA].[San Francisco]}
      {[Store].[USA].[OR]}
      Row #0: 100,827
      Row #1: 100,827
      Row #2: 74,748
      Row #3:
      Row #4: 21,333
      Row #5: 25,663
      Row #6: 25,635
      Row #7: 2,117
      Row #8: 26,079
    RESULT

    assert_query_returns(goodman_connection(ROLLUP_POLICY::FULL), query, <<~'RESULT')
      Axis #0:
      {[Time].[1997]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[All Stores]}
      {[Store].[USA]}
      {[Store].[USA].[CA]}
      {[Store].[USA].[CA].[Alameda]}
      {[Store].[USA].[CA].[Beverly Hills]}
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Diego]}
      {[Store].[USA].[CA].[San Francisco]}
      {[Store].[USA].[OR]}
      Row #0: 266,773
      Row #1: 266,773
      Row #2: 74,748
      Row #3:
      Row #4: 21,333
      Row #5: 25,663
      Row #6: 25,635
      Row #7: 2,117
      Row #8: 67,659
    RESULT

    assert_query_returns(goodman_connection(ROLLUP_POLICY::HIDDEN), query, <<~'RESULT')
      Axis #0:
      {[Time].[1997]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[All Stores]}
      {[Store].[USA]}
      {[Store].[USA].[CA]}
      {[Store].[USA].[CA].[Alameda]}
      {[Store].[USA].[CA].[Beverly Hills]}
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[San Diego]}
      {[Store].[USA].[CA].[San Francisco]}
      {[Store].[USA].[OR]}
      Row #0:
      Row #1:
      Row #2: 74,748
      Row #3:
      Row #4: 21,333
      Row #5: 25,663
      Row #6: 25,635
      Row #7: 2,117
      Row #8:
    RESULT
    check_query(olap, query)
  end

  # MONDRIAN-402: the access control elements for hierarchies with the same
  # name in different cubes could not be distinguished.
  # Java: AccessControlTest#testBugMondrian402
  it "should distinguish the grants of hierarchies with the same name in different cubes" do
    olap = role_connection(<<~'XML', 'California manager')
      <Role name="California manager">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" access="none" />
          </CubeGrant>
          <CubeGrant cube="Sales Ragged" access="all">
            <HierarchyGrant hierarchy="[Store]" access="custom" />
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
    assert_hierarchy_access(olap, Access::NONE, "Sales", "Store")
    assert_hierarchy_access(olap, Access::CUSTOM, "Sales Ragged", "Store")
  end

  # Java: AccessControlTest#testPartialRollupParentChildHierarchy
  it "should apply the partial rollup to a parent-child hierarchy" do
    olap = role_connection(<<~'XML', 'Buggy Role')
      <Role name="Buggy Role">
        <SchemaGrant access="none">
          <CubeGrant cube="HR" access="all">
            <HierarchyGrant hierarchy="[Employees]" access="custom"
                            rollupPolicy="partial">
              <MemberGrant
                  member="[Employees].[All Employees].[Sheri Nowmer].[Darren Stanz]"
                  access="all"/>
            </HierarchyGrant>
            <HierarchyGrant hierarchy="[Store]" access="custom"
                            rollupPolicy="partial">
              <MemberGrant member="[Store].[All Stores].[USA].[CA]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML

    mdx = "select\n  {[Measures].[Number of Employees]} on columns,\n  {[Store]} on rows\nfrom HR"
    assert_query_returns(olap, mdx, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Number of Employees]}
      Axis #2:
      {[Store].[All Stores]}
      Row #0: 1
    RESULT
    check_query(olap, mdx)

    mdx2 = "select\n  {[Measures].[Number of Employees]} on columns,\n  {[Employees]} on rows\nfrom HR"
    assert_query_returns(olap, mdx2, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Number of Employees]}
      Axis #2:
      {[Employees].[All Employees]}
      Row #0: 1
    RESULT
    check_query(olap, mdx2)
  end

  # Java: AccessControlTest#testParentChildUserDefinedRole
  it "should apply a user-defined role to a parent-child hierarchy" do
    olap = foodmart_connection
    connection = olap.raw_mondrian_connection
    saved_role = connection.getRole
    begin
      # Run queries as top-level employee.
      connection.setRole(people_role(saved_role, connection.getSchema, "Sheri Nowmer"))
      assert_expression_returns(olap, "[Employees].Members.Count", "1,156", cube: "HR")

      # Level 2 employee
      connection.setRole(people_role(saved_role, connection.getSchema, "Derrick Whelply"))
      assert_expression_returns(olap, "[Employees].Members.Count", "605", cube: "HR")
      assert_axis_returns(olap, "Head([Employees].Members, 4),Tail([Employees].Members, 2)", <<~'AXIS', cube: "HR")
        [Employees].[All Employees]
        [Employees].[Sheri Nowmer]
        [Employees].[Sheri Nowmer].[Derrick Whelply]
        [Employees].[Sheri Nowmer].[Derrick Whelply].[Beverly Baker]
        [Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Ed Young].[Gregory Whiting].[Merrill Steel]
        [Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Ed Young].[Gregory Whiting].[Melissa Marple]
      AXIS

      # Leaf employee
      connection.setRole(people_role(saved_role, connection.getSchema, "Ann Weyerhaeuser"))
      assert_expression_returns(olap, "[Employees].Members.Count", "7", cube: "HR")
      assert_axis_returns(olap, "[Employees].Members", <<~'AXIS', cube: "HR")
        [Employees].[All Employees]
        [Employees].[Sheri Nowmer]
        [Employees].[Sheri Nowmer].[Derrick Whelply]
        [Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges]
        [Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Cody Goldey]
        [Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Cody Goldey].[Shanay Steelman]
        [Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Cody Goldey].[Shanay Steelman].[Ann Weyerhaeuser]
      AXIS
    ensure
      connection.setRole(saved_role)
    end
  end

  # BISERVER-1574: Cube role rollupPolicy='partial' failure. The problem was a
  # NullPointerException in SchemaReader#getMemberParent when called on the
  # members returned in a result set.
  # Java: AccessControlTest#testBugBiserver1574
  it "should give the parent of a member of a result with the partial rollup policy" do
    olap = role_connection(BI_SERVER_1574_ROLE1, 'role1')
    mdx = "select {([Measures].[Store Invoice], [Store Size in SQFT].[All Store Size in SQFTs])} ON COLUMNS,\n" \
      "  {[Warehouse].[All Warehouses]} ON ROWS\nfrom [Warehouse]"
    check_query(olap, mdx)
    assert_query_returns(olap, mdx, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Store Invoice], [Store Size in SQFT].[All Store Size in SQFTs]}
      Axis #2:
      {[Warehouse].[All Warehouses]}
      Row #0: 4,042.96
    RESULT
  end

  # MONDRIAN-435: Internal error in HierarchizeArrayComparator. It occurs when
  # Hierarchize applies to tuples on a hierarchy with partial rollup.
  # Java: AccessControlTest#testBugMondrian435
  it "should hierarchize tuples of a hierarchy with the partial rollup policy" do
    olap = role_connection(BI_SERVER_1574_ROLE1, 'role1')

    # minimal testcase
    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select hierarchize(    crossjoin({[Store Size in SQFT], [Store Size in SQFT].Children}, {[Product]})) on 0,[Store Type].Members on 1 from [Warehouse]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Store Size in SQFT].[All Store Size in SQFTs], [Product].[All Products]}
      {[Store Size in SQFT].[20319], [Product].[All Products]}
      Axis #2:
      {[Store Type].[All Store Types]}
      {[Store Type].[Supermarket]}
      Row #0: 4,042.96
      Row #0: 4,042.96
      Row #1: 4,042.96
      Row #1: 4,042.96
    RESULT

    # explicit tuples, not crossjoin
    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select hierarchize(    { ([Store Size in SQFT], [Product]),
            ([Store Size in SQFT].[20319], [Product].[Food]),
            ([Store Size in SQFT], [Product].[Drink].[Dairy]),
            ([Store Size in SQFT].[20319], [Product]) }
      ) on 0,[Store Type].Members on 1 from [Warehouse]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Store Size in SQFT].[All Store Size in SQFTs], [Product].[All Products]}
      {[Store Size in SQFT].[All Store Size in SQFTs], [Product].[Drink].[Dairy]}
      {[Store Size in SQFT].[20319], [Product].[All Products]}
      {[Store Size in SQFT].[20319], [Product].[Food]}
      Axis #2:
      {[Store Type].[All Store Types]}
      {[Store Type].[Supermarket]}
      Row #0: 4,042.96
      Row #0: 82.454
      Row #0: 4,042.96
      Row #0: 2,696.758
      Row #1: 4,042.96
      Row #1: 82.454
      Row #1: 4,042.96
      Row #1: 2,696.758
    RESULT

    # extended testcase; note that [Store Size in SQFT].Parent is null,
    # so disappears
    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select non empty hierarchize(union(  union(    crossjoin({[Store Size in SQFT]}, {[Product]}),    crossjoin({[Store Size in SQFT], [Store Size in SQFT].Children}, {[Product]}),    all),  union(    crossjoin({[Store Size in SQFT].Parent}, {[Product].[Drink]}),    crossjoin({[Store Size in SQFT].Children}, {[Product].[Food]}),    all),  all)) on 0,[Store Type].Members on 1 from [Warehouse]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Store Size in SQFT].[All Store Size in SQFTs], [Product].[All Products]}
      {[Store Size in SQFT].[All Store Size in SQFTs], [Product].[All Products]}
      {[Store Size in SQFT].[20319], [Product].[All Products]}
      {[Store Size in SQFT].[20319], [Product].[Food]}
      Axis #2:
      {[Store Type].[All Store Types]}
      {[Store Type].[Supermarket]}
      Row #0: 4,042.96
      Row #0: 4,042.96
      Row #0: 4,042.96
      Row #0: 2,696.758
      Row #1: 4,042.96
      Row #1: 4,042.96
      Row #1: 4,042.96
      Row #1: 2,696.758
    RESULT

    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select Hierarchize(
        CrossJoin
      (    CrossJoin(
            {[Product].[All Products],        [Product].[Food],
             [Product].[Food].[Eggs],
             [Product].[Drink].[Dairy]},
            [Store Type].MEMBERS),
          [Store Size in SQFT].MEMBERS),
        PRE) on 0
      from [Warehouse]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Product].[All Products], [Store Type].[All Store Types], [Store Size in SQFT].[All Store Size in SQFTs]}
      {[Product].[All Products], [Store Type].[All Store Types], [Store Size in SQFT].[20319]}
      {[Product].[All Products], [Store Type].[Supermarket], [Store Size in SQFT].[All Store Size in SQFTs]}
      {[Product].[All Products], [Store Type].[Supermarket], [Store Size in SQFT].[20319]}
      {[Product].[Drink].[Dairy], [Store Type].[All Store Types], [Store Size in SQFT].[All Store Size in SQFTs]}
      {[Product].[Drink].[Dairy], [Store Type].[All Store Types], [Store Size in SQFT].[20319]}
      {[Product].[Drink].[Dairy], [Store Type].[Supermarket], [Store Size in SQFT].[All Store Size in SQFTs]}
      {[Product].[Drink].[Dairy], [Store Type].[Supermarket], [Store Size in SQFT].[20319]}
      {[Product].[Food], [Store Type].[All Store Types], [Store Size in SQFT].[All Store Size in SQFTs]}
      {[Product].[Food], [Store Type].[All Store Types], [Store Size in SQFT].[20319]}
      {[Product].[Food], [Store Type].[Supermarket], [Store Size in SQFT].[All Store Size in SQFTs]}
      {[Product].[Food], [Store Type].[Supermarket], [Store Size in SQFT].[20319]}
      {[Product].[Food].[Eggs], [Store Type].[All Store Types], [Store Size in SQFT].[All Store Size in SQFTs]}
      {[Product].[Food].[Eggs], [Store Type].[All Store Types], [Store Size in SQFT].[20319]}
      {[Product].[Food].[Eggs], [Store Type].[Supermarket], [Store Size in SQFT].[All Store Size in SQFTs]}
      {[Product].[Food].[Eggs], [Store Type].[Supermarket], [Store Size in SQFT].[20319]}
      Row #0: 4,042.96
      Row #0: 4,042.96
      Row #0: 4,042.96
      Row #0: 4,042.96
      Row #0: 82.454
      Row #0: 82.454
      Row #0: 82.454
      Row #0: 82.454
      Row #0: 2,696.758
      Row #0: 2,696.758
      Row #0: 2,696.758
      Row #0: 2,696.758
      Row #0:
      Row #0:
      Row #0:
      Row #0:
    RESULT
  end

  def check_bug_mondrian_436
    assert_query_returns(role_connection(BI_SERVER_1574_ROLE1, 'role1'), <<~'MDX', <<~'RESULT')
      select non empty {[Measures].[Units Ordered],
                  [Measures].[Units Shipped]} on 0,
      non empty hierarchize(
          union(
              crossjoin(
                  {[Store Size in SQFT]},
                  {[Product].[Drink],
                   [Product].[Food],
                   [Product].[Drink].[Dairy]}),
              crossjoin(
                  {[Store Size in SQFT].[20319]},
                  {[Product].Children}))) on 1
      from [Warehouse]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Units Ordered]}
      {[Measures].[Units Shipped]}
      Axis #2:
      {[Store Size in SQFT].[All Store Size in SQFTs], [Product].[Drink]}
      {[Store Size in SQFT].[All Store Size in SQFTs], [Product].[Drink].[Dairy]}
      {[Store Size in SQFT].[All Store Size in SQFTs], [Product].[Food]}
      {[Store Size in SQFT].[20319], [Product].[Drink]}
      {[Store Size in SQFT].[20319], [Product].[Food]}
      {[Store Size in SQFT].[20319], [Product].[Non-Consumable]}
      Row #0: 865.0
      Row #0: 767.0
      Row #1: 195.0
      Row #1: 182.0
      Row #2: 6065.0
      Row #2: 5723.0
      Row #3: 865.0
      Row #3: 767.0
      Row #4: 6065.0
      Row #4: 5723.0
      Row #5: 2179.0
      Row #5: 2025.0
    RESULT
  end

  NATIVE_PROPERTIES = {
    EnableNativeCrossJoin: true,
    EnableNativeFilter: true,
    EnableNativeNonEmpty: true,
    EnableNativeTopCount: true,
    ExpandNonNative: true
  }.freeze

  # MONDRIAN-436: SubstitutingMemberReader.getMemberBuilder gives
  # UnsupportedOperationException.
  # Java: AccessControlTest#testBugMondrian436
  it "should give a member builder for a substituting member reader" do
    # Run with native enabled, then with whatever properties are set for
    # this test run.
    with_mondrian_properties(NATIVE_PROPERTIES) { check_bug_mondrian_436 }
    check_bug_mondrian_436
  end

  # MONDRIAN-456: hierarchy access control works on a virtual cube.
  # Java: AccessControlTest#testVirtualCube
  it "should apply the hierarchy grants on a virtual cube" do
    olap = role_connection(<<~'XML', 'VCRole')
      <Role name="VCRole">
        <SchemaGrant access="none">
          <CubeGrant cube="Warehouse and Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" access="custom">
              <MemberGrant member="[Store].[USA].[CA]" access="all"/>
              <MemberGrant member="[Store].[USA].[CA].[Los Angeles]" access="none"/>
            </HierarchyGrant>
            <HierarchyGrant hierarchy="[Customers]" access="custom"
                topLevel="[Customers].[State Province]" bottomLevel="[Customers].[City]">
              <MemberGrant member="[Customers].[USA].[CA]" access="all"/>
              <MemberGrant member="[Customers].[USA].[CA].[Los Angeles]" access="none"/>
            </HierarchyGrant>
            <HierarchyGrant hierarchy="[Gender]" access="none"/>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
    assert_query_returns(olap, "select [Store].Members on 0 from [Warehouse and Sales]", <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Store].[All Stores]}
      {[Store].[USA]}
      {[Store].[USA].[CA]}
      {[Store].[USA].[CA].[Alameda]}
      {[Store].[USA].[CA].[Alameda].[HQ]}
      {[Store].[USA].[CA].[Beverly Hills]}
      {[Store].[USA].[CA].[Beverly Hills].[Store 6]}
      {[Store].[USA].[CA].[San Diego]}
      {[Store].[USA].[CA].[San Diego].[Store 24]}
      {[Store].[USA].[CA].[San Francisco]}
      {[Store].[USA].[CA].[San Francisco].[Store 14]}
      Row #0: 159,167.84
      Row #0: 159,167.84
      Row #0: 159,167.84
      Row #0:
      Row #0:
      Row #0: 45,750.24
      Row #0: 45,750.24
      Row #0: 54,431.14
      Row #0: 54,431.14
      Row #0: 4,441.18
      Row #0: 4,441.18
    RESULT
  end

  # BISERVER-2491: rollupPolicy=partial and queries to upper members don't work.
  # Java: AccessControlTest#testBugBiserver2491
  it "should query the upper members with the partial rollup policy" do
    olap = role_connection(<<~'XML', 'role2')
      <Role name="role2"> <SchemaGrant access="none">  <CubeGrant cube="Sales" access="all">   <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="partial">    <MemberGrant member="[Store].[USA].[CA]" access="all"/>    <MemberGrant member="[Store].[USA].[CA].[Los Angeles]" access="none"/>   </HierarchyGrant>  </CubeGrant> </SchemaGrant></Role>
    XML

    first_broken_mdx =
      "select [Measures].[Unit Sales] ON COLUMNS, {[Store].[Store Country].Members} ON ROWS from [Sales]"

    check_query(olap, first_broken_mdx)
    assert_query_returns(olap, first_broken_mdx, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA]}
      Row #0: 49,085
    RESULT

    second_broken_mdx =
      "select [Measures].[Unit Sales] ON COLUMNS, Descendants([Store],[Store].[Store Name]) ON ROWS from [Sales]"
    check_query(olap, second_broken_mdx)
    assert_query_returns(olap, second_broken_mdx, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA].[CA].[Alameda].[HQ]}
      {[Store].[USA].[CA].[Beverly Hills].[Store 6]}
      {[Store].[USA].[CA].[San Diego].[Store 24]}
      {[Store].[USA].[CA].[San Francisco].[Store 14]}
      Row #0:
      Row #1: 21,333
      Row #2: 25,635
      Row #3: 2,117
    RESULT
  end

  # MONDRIAN-622: Poor performance with large union role.
  # Java: AccessControlTest#testBugMondrian622
  it "should execute a query with a large union role" do
    cube_name = "Sales with multiple customers"
    roles = +""
    role_usages = +""
    result = foodmart_connection.raw_mondrian_connection.then do |connection|
      connection.execute(connection.parseQuery("select [Customers].[City].Members on 0 from [Sales]"))
    end
    result.getAxes[0].getPositions.each do |position|
      member = position.get(0)
      name = "#{member.getParentMember.getName}.#{member.getName}" # e.g. "BC.Burnaby"
      # e.g. "[Customers].[State Province].[BC].[Burnaby]"
      unique_name = member.getUniqueName.gsub(".[All Customers]", "")
      # e.g. "[Customers2].[State Province].[BC].[Burnaby]"
      unique_name2 = unique_name.gsub("Customers", "Customers2")
      # e.g. "[Customers3].[State Province].[BC].[Burnaby]"
      unique_name3 = unique_name.gsub("Customers", "Customers3")
      roles << <<~XML
        <Role name="#{name}">
          <SchemaGrant access="none">
            <CubeGrant access="all" cube="#{cube_name}">
              <HierarchyGrant access="custom" hierarchy="[Customers]" rollupPolicy="partial">
                <MemberGrant access="all" member="#{unique_name}"/>
              </HierarchyGrant>
              <HierarchyGrant access="custom" hierarchy="[Customers2]" rollupPolicy="partial">
                <MemberGrant access="all" member="#{unique_name2}"/>
              </HierarchyGrant>
              <HierarchyGrant access="custom" hierarchy="[Customers3]" rollupPolicy="partial">
                <MemberGrant access="all" member="#{unique_name3}"/>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML
      role_usages << %(    <RoleUsage roleName="#{name}"/>\n)
    end
    schema = foodmart_schema(
      parameter_defs: <<~'XML',
        <Dimension name="Customers">
          <Hierarchy hasAll="true" primaryKey="customer_id">
            <Table name="customer"/>
            <Level name="Country" column="country" uniqueMembers="true"/>
            <Level name="State Province" column="state_province" uniqueMembers="true"/>
            <Level name="City" column="city" uniqueMembers="false"/>
            <Level name="Name" column="customer_id" type="Numeric" uniqueMembers="true"/>
          </Hierarchy>
        </Dimension>
      XML
      cube_defs: <<~XML,
        <Cube name="#{cube_name}">
          <Table name="sales_fact_1997"/>
          <DimensionUsage name="Time" source="Time" foreignKey="time_id"/>
          <DimensionUsage name="Product" source="Product" foreignKey="product_id"/>
          <DimensionUsage name="Customers" source="Customers" foreignKey="customer_id"/>
          <DimensionUsage name="Customers2" source="Customers" foreignKey="customer_id"/>
          <DimensionUsage name="Customers3" source="Customers" foreignKey="customer_id"/>
          <Measure name="Unit Sales" column="unit_sales" aggregator="sum" formatString="Standard"/>
        </Cube>
      XML
      role_defs: "#{roles}  <Role name=\"Test\">\n    <Union>\n#{role_usages}    </Union>\n  </Role>\n"
    )
    foodmart_connection(schema, role: 'Test').execute("select from [#{cube_name}]")
  end

  # MONDRIAN-694: Incorrect handling of child/parent relationship with
  # hierarchy grants.
  # Java: AccessControlTest#testBugMondrian694
  it "should handle the child and parent relationship with hierarchy grants" do
    olap = role_connection(<<~'XML', 'REG1')
      <Role name="REG1">
        <SchemaGrant access="none">
          <CubeGrant cube="HR" access="all">
            <HierarchyGrant hierarchy="Employees" access="custom" rollupPolicy="partial">
              <MemberGrant member="[Employees].[All Employees]" access="none"/>
              <MemberGrant member="[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Cody Goldey].[Shanay Steelman].[Steven Betsekas]" access="all"/>
              <MemberGrant member="[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Cody Goldey].[Shanay Steelman].[Arvid Ziegler]" access="all"/>
              <MemberGrant member="[Employees].[Sheri Nowmer].[Derrick Whelply].[Laurie Borges].[Cody Goldey].[Shanay Steelman].[Ann Weyerhaeuser]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML

    # With bug MONDRIAN-694 returns 874.80, should return 79.20.
    # Test case is minimal: doesn't happen without the Crossjoin, or
    # without the NON EMPTY, or with [Employees] as opposed to
    # [Employees].[All Employees], or with [Department].[All Departments].
    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select NON EMPTY {[Measures].[Org Salary]} ON COLUMNS,
      NON EMPTY Crossjoin({[Department].[14]}, {[Employees].[All Employees]}) ON ROWS
      from [HR]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Org Salary]}
      Axis #2:
      {[Department].[14], [Employees].[All Employees]}
      Row #0: $97.20
    RESULT

    # This query gave the right answer, even with MONDRIAN-694.
    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select NON EMPTY {[Measures].[Org Salary]} ON COLUMNS,
      NON EMPTY Hierarchize(Crossjoin({[Department].[14]}, {[Employees].[All Employees], [Employees].Children})) ON ROWS
      from [HR]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Org Salary]}
      Axis #2:
      {[Department].[14], [Employees].[All Employees]}
      {[Department].[14], [Employees].[Sheri Nowmer]}
      Row #0: $97.20
      Row #1: $97.20
    RESULT

    # Original test case, not quite minimal. With MONDRIAN-694, returns
    # $874.80 for [All Employees].
    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select NON EMPTY {[Measures].[Org Salary]} ON COLUMNS,
      NON EMPTY Hierarchize(Union(Crossjoin({[Department].[All Departments].[14]}, {[Employees].[All Employees]}), Crossjoin({[Department].[All Departments].[14]}, [Employees].[All Employees].Children))) ON ROWS
      from [HR]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Org Salary]}
      Axis #2:
      {[Department].[14], [Employees].[All Employees]}
      {[Department].[14], [Employees].[Sheri Nowmer]}
      Row #0: $97.20
      Row #1: $97.20
    RESULT

    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select NON EMPTY {[Measures].[Org Salary]} ON COLUMNS,
      NON EMPTY Crossjoin(Hierarchize(Union({[Employees].[All Employees]}, [Employees].[All Employees].Children)), {[Department].[14]}) ON ROWS
      from [HR]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Org Salary]}
      Axis #2:
      {[Employees].[All Employees], [Department].[14]}
      {[Employees].[Sheri Nowmer], [Department].[14]}
      Row #0: $97.20
      Row #1: $97.20
    RESULT
  end

  # MONDRIAN-722: if ignoreInvalidMembers=true, should ignore grants with
  # invalid members.
  # Java: AccessControlTest#testBugMondrian722
  it "should ignore the grants with invalid members" do
    with_mondrian_properties(IgnoreInvalidMembers: true) do
      olap = role_connection(<<~'XML', 'CTO')
        <Role name="CTO">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Customers]" access="custom">
                <MemberGrant member="[Customers].[USA].[XX]" access="none"/>
                <MemberGrant member="[Customers].[USA].[XX].[Yyy Yyyyyyy]" access="all"/>
                <MemberGrant member="[Customers].[USA]" access="none"/>
                <MemberGrant member="[Customers].[USA].[CA]" access="none"/>
                <MemberGrant member="[Customers].[USA].[CA].[Los Angeles]" access="all"/>
                <MemberGrant member="[Customers].[USA].[CA].[Zzz Zzzz]" access="none"/>
                <MemberGrant member="[Customers].[USA].[CA].[San Francisco]" access="all"/>
              </HierarchyGrant>
              <HierarchyGrant hierarchy="[Gender]" access="none"/>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML
      assert_query_returns(olap, <<~'MDX', <<~'RESULT')
        select [Measures] on 0,
         Hierarchize(
           {[Customers].[USA].Children,
            [Customers].[USA].[CA].Children}) on 1
        from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Customers].[USA].[CA]}
        {[Customers].[USA].[CA].[Los Angeles]}
        {[Customers].[USA].[CA].[San Francisco]}
        Row #0: 74,748
        Row #1: 2,009
        Row #2: 88
      RESULT
    end
  end

  def check_calc_member_level(olap)
    connection = olap.raw_mondrian_connection
    result = connection.execute(connection.parseQuery(<<~'MDX'))
      with member [Store].[USA].[CA].[Foo] as
       1
      select {[Measures].[Unit Sales]} on columns,
      {[Store].[USA].[CA],
       [Store].[USA].[CA].[Los Angeles],
       [Store].[USA].[CA].[Foo]} on rows
      from [Sales]
    MDX
    row_positions = result.getAxes[1].getPositions
    member0 = row_positions.get(0).get(0)
    assert_equal "CA", member0.getName
    assert_equal "Store State", member0.getLevel.getName
    member1 = row_positions.get(1).get(0)
    assert_equal "Los Angeles", member1.getName
    assert_equal "Store City", member1.getLevel.getName
    member2 = row_positions.get(2).get(0)
    assert_equal "Foo", member2.getName
    assert_equal "Store City", member2.getLevel.getName
  end

  # MONDRIAN-746: Report returns stack trace when turning on subtotals on a
  # hierarchy with top level hidden.
  # Java: AccessControlTest#testCalcMemberLevel
  it "should give the level of a calculated member below a hidden top level" do
    check_calc_member_level(foodmart_connection)
    check_calc_member_level(role_connection(<<~'XML', 'Role1'))
      <Role name="Role1">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="Partial" topLevel="[Store].[Store State]">
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
  end

  # MONDRIAN-568: grants on OLAP elements are validated by name, thus
  # granting implicit access to all cubes which have a dimension with the
  # same name.
  # Java: AccessControlTest#testBugMondrian568
  it "should not grant access to a measure of another cube with the same dimension name" do
    schema = foodmart_schema(role_defs: <<~'XML')
      <Role name="Role1">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="none">
            <HierarchyGrant hierarchy="[Measures]" access="custom">
              <MemberGrant member="[Measures].[Unit Sales]" access="all"/>
            </HierarchyGrant>    </CubeGrant>
        </SchemaGrant>
      </Role>
      <Role name="Role2">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales Ragged" access="all"/>
        </SchemaGrant>
      </Role>
    XML

    assert_member_access(foodmart_connection(schema, role: 'Role1'), Access::NONE, "[Measures].[Store Cost]")
    assert_member_access(foodmart_connection(schema, role: 'Role1,Role2'), Access::NONE, "[Measures].[Store Cost]")
  end

  # MONDRIAN-935: no results when some level members in a member grant have
  # no data.
  # Java: AccessControlTest#testBugMondrian935
  it "should return results when some members of a member grant have no data" do
    olap = role_connection(<<~'XML', 'Role1')
      <Role name='Role1'>
        <SchemaGrant access='none'>
          <CubeGrant cube='Sales' access='all'>
            <HierarchyGrant hierarchy='[Store Type]' access='custom' rollupPolicy='partial'>
              <MemberGrant member='[Store Type].[All Store Types]' access='none'/>
              <MemberGrant member='[Store Type].[Supermarket]' access='all'/>
            </HierarchyGrant>
            <HierarchyGrant hierarchy='[Customers]' access='custom' rollupPolicy='partial' >
              <MemberGrant member='[Customers].[All Customers]' access='none'/>
              <MemberGrant member='[Customers].[USA].[WA]' access='all'/>
              <MemberGrant member='[Customers].[USA].[CA]' access='none'/>
              <MemberGrant member='[Customers].[USA].[CA].[Los Angeles]' access='all'/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML

    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select [Measures] on 0,
      [Customers].[USA].Children * [Store Type].Children on 1
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Customers].[USA].[CA], [Store Type].[Supermarket]}
      {[Customers].[USA].[WA], [Store Type].[Supermarket]}
      Row #0: 1,118
      Row #1: 73,178
    RESULT
  end

  # Java: AccessControlTest#testDimensionGrant
  it "should apply the dimension grants" do
    schema = foodmart_schema(role_defs: <<~'XML')
      <Role name="Role1">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="custom">
            <DimensionGrant dimension="[Measures]" access="all" />
            <DimensionGrant dimension="[Education Level]" access="all" />
            <DimensionGrant dimension="[Gender]" access="all" />
          </CubeGrant>
        </SchemaGrant>
      </Role>
      <Role name="Role2">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="custom">
            <DimensionGrant dimension="[Measures]" access="all" />
            <DimensionGrant dimension="[Education Level]" access="all" />
            <DimensionGrant dimension="[Customers]" access="none" />
          </CubeGrant>
        </SchemaGrant>
      </Role>
      <Role name="Role3">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="custom">
            <DimensionGrant dimension="[Education Level]" access="all" />
            <DimensionGrant dimension="[Measures]" access="custom" />
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
    role1 = foodmart_connection(schema, role: 'Role1')
    assert_axis_returns(role1, "[Education Level].Members", <<~'AXIS')
      [Education Level].[All Education Levels]
      [Education Level].[Bachelors Degree]
      [Education Level].[Graduate Degree]
      [Education Level].[High School Degree]
      [Education Level].[Partial College]
      [Education Level].[Partial High School]
    AXIS
    assert_axis_raises(role1, "[Customers].Members",
      "Mondrian Error:Failed to parse query 'select {[Customers].Members} on columns from Sales'")
    assert_axis_raises(foodmart_connection(schema, role: 'Role2'), "[Customers].Members",
      "Mondrian Error:Failed to parse query 'select {[Customers].Members} on columns from Sales'")
    assert_query_returns(role1,
      "select {[Education Level].Members} on columns, {[Measures].[Unit Sales]} on rows from Sales",
      <<~'RESULT')
        Axis #0:
        {}
        Axis #1:
        {[Education Level].[All Education Levels]}
        {[Education Level].[Bachelors Degree]}
        {[Education Level].[Graduate Degree]}
        {[Education Level].[High School Degree]}
        {[Education Level].[Partial College]}
        {[Education Level].[Partial High School]}
        Axis #2:
        {[Measures].[Unit Sales]}
        Row #0: 266,773
        Row #0: 68,839
        Row #0: 15,570
        Row #0: 78,664
        Row #0: 24,545
        Row #0: 79,155
      RESULT
    mdx = "select {[Education Level].Members} on columns, {[Measures].[Unit Sales]} on rows from Sales"
    assert_error_chain_includes("Mondrian Error:Failed to parse query '#{mdx}'") do
      foodmart_connection(schema, role: 'Role3').execute(mdx)
    end
  end

  # MONDRIAN-1030: when the top level of a hierarchy is not accessible and the
  # rollup policy is partial, the results were those of the first accessible
  # member only.
  #
  # If a union of roles gives access to two sibling root members and the query
  # does not include their level, the cell data was that of the first sibling
  # and excluded that of the second.
  #
  # The RolapEvaluator cannot represent a default member as many members, and
  # because the default member is not the all member, it constrained the SQL
  # to the first member only. Mondrian now disguises the root member in the
  # evaluator as a RestrictedMemberReader.MultiCardinalityDefaultMember.
  # RolapHierarchy.LimitedRollupSubstitutingMemberReader recognizes it and
  # uses the rollup policy of the parent member to generate the SQL.
  # Java: AccessControlTest#testMondrian1030
  it "should roll up the accessible root members of a union role" do
    mdx1 = <<~'MDX'
      With
      Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Customers],[*BASE_MEMBERS_Product])'
      Set [*SORTED_ROW_AXIS] as 'Order([*CJ_ROW_AXIS],[Customers].CurrentMember.OrderKey,BASC,[Education Level].CurrentMember.OrderKey,BASC)'
      Set [*BASE_MEMBERS_Customers] as '[Customers].[City].Members'
      Set [*BASE_MEMBERS_Product] as '[Education Level].Members'
      Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}'
      Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Customers].currentMember,[Education Level].currentMember)})'
      Set [*CJ_COL_AXIS] as '[*NATIVE_CJ_SET]'
      Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Unit Sales]', FORMAT_STRING = '#,###', SOLVE_ORDER=400
      Select
      [*BASE_MEMBERS_Measures] on columns,
      Non Empty [*SORTED_ROW_AXIS] on rows
      From [Sales]
    MDX
    mdx2 = <<~'MDX'
      With
      Set [*BASE_MEMBERS_Product] as '[Education Level].Members'
      Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}'
      Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Unit Sales]', FORMAT_STRING = '#,###', SOLVE_ORDER=400
      Select
      [*BASE_MEMBERS_Measures] on columns,
      Non Empty [*BASE_MEMBERS_Product] on rows
      From [Sales]
    MDX
    schema = foodmart_schema(role_defs: <<~'XML')
        <Role name="Role1">
          <SchemaGrant access="all">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Customers]" access="custom" topLevel="[Customers].[City]" bottomLevel="[Customers].[City]" rollupPolicy="partial">
                <MemberGrant member="[City].[Coronado]" access="all">
                </MemberGrant>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
        <Role name="Role2">
          <SchemaGrant access="all">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Customers]" access="custom" topLevel="[Customers].[City]" bottomLevel="[Customers].[City]" rollupPolicy="partial">
                <MemberGrant member="[City].[Burbank]" access="all">
                </MemberGrant>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
    XML
    role1 = foodmart_connection(schema, role: 'Role1')
    role2 = foodmart_connection(schema, role: 'Role2')
    role12 = foodmart_connection(schema, role: 'Role1,Role2')
    # Control tests
    assert_query_returns(role1, mdx1, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Customers].[USA].[CA].[Coronado], [Education Level].[All Education Levels]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[Bachelors Degree]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[Graduate Degree]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[High School Degree]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[Partial College]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[Partial High School]}
      Row #0: 2,391
      Row #1: 559
      Row #2: 205
      Row #3: 551
      Row #4: 253
      Row #5: 823
    RESULT
    assert_query_returns(role2, mdx1, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Customers].[USA].[CA].[Burbank], [Education Level].[All Education Levels]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[Bachelors Degree]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[Graduate Degree]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[High School Degree]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[Partial College]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[Partial High School]}
      Row #0: 3,086
      Row #1: 914
      Row #2: 126
      Row #3: 1,029
      Row #4: 286
      Row #5: 731
    RESULT
    assert_query_returns(role12, mdx1, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Customers].[USA].[CA].[Burbank], [Education Level].[All Education Levels]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[Bachelors Degree]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[Graduate Degree]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[High School Degree]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[Partial College]}
      {[Customers].[USA].[CA].[Burbank], [Education Level].[Partial High School]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[All Education Levels]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[Bachelors Degree]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[Graduate Degree]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[High School Degree]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[Partial College]}
      {[Customers].[USA].[CA].[Coronado], [Education Level].[Partial High School]}
      Row #0: 3,086
      Row #1: 914
      Row #2: 126
      Row #3: 1,029
      Row #4: 286
      Row #5: 731
      Row #6: 2,391
      Row #7: 559
      Row #8: 205
      Row #9: 551
      Row #10: 253
      Row #11: 823
    RESULT
    # Actual tests
    assert_query_returns(role1, mdx2, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Education Level].[All Education Levels]}
      {[Education Level].[Bachelors Degree]}
      {[Education Level].[Graduate Degree]}
      {[Education Level].[High School Degree]}
      {[Education Level].[Partial College]}
      {[Education Level].[Partial High School]}
      Row #0: 2,391
      Row #1: 559
      Row #2: 205
      Row #3: 551
      Row #4: 253
      Row #5: 823
    RESULT
    assert_query_returns(role2, mdx2, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Education Level].[All Education Levels]}
      {[Education Level].[Bachelors Degree]}
      {[Education Level].[Graduate Degree]}
      {[Education Level].[High School Degree]}
      {[Education Level].[Partial College]}
      {[Education Level].[Partial High School]}
      Row #0: 3,086
      Row #1: 914
      Row #2: 126
      Row #3: 1,029
      Row #4: 286
      Row #5: 731
    RESULT
    assert_query_returns(role12, mdx2, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Education Level].[All Education Levels]}
      {[Education Level].[Bachelors Degree]}
      {[Education Level].[Graduate Degree]}
      {[Education Level].[High School Degree]}
      {[Education Level].[Partial College]}
      {[Education Level].[Partial High School]}
      Row #0: 5,477
      Row #1: 1,473
      Row #2: 331
      Row #3: 1,580
      Row #4: 539
      Row #5: 1,554
    RESULT
  end

  # MONDRIAN-1030: a query on a level above a level with access control
  # constrained only at the current level with the partial rollup policy.
  # Example: a query on USA where only Los Angeles is accessible returned the
  # values for California instead of only Los Angeles.
  # Java: AccessControlTest#testBugMondrian1030_2
  it "should constrain an upper level to the accessible members of a lower level" do
    olap = role_connection(<<~'XML', 'Bacon')
      <Role name="Bacon">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="partial">
              <MemberGrant member="[Customers].[USA].[CA].[Los Angeles]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
    assert_query_returns(olap, "select {[Measures].[Unit Sales]} on 0,\n   {[Customers].[USA]} on 1\nfrom [Sales]",
      <<~'RESULT')
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Customers].[USA]}
        Row #0: 2,009
      RESULT
  end

  # MONDRIAN-1091: RoleImpl searched for member grants by object identity
  # rather than unique name. With the partial rollup policy the members are
  # wrapped, so identity checks failed.
  # Java: AccessControlTest#testMondrian1091
  it "should find the member grants of wrapped members" do
    olap = role_connection(<<~'XML', 'Role1')
      <Role name="Role1">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="partial">
              <MemberGrant member="[Store].[USA].[CA]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
    assert_query_returns(olap, "select {[Store].Members} on columns from [Sales]", <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Store].[All Stores]}
      {[Store].[USA]}
      {[Store].[USA].[CA]}
      {[Store].[USA].[CA].[Alameda]}
      {[Store].[USA].[CA].[Alameda].[HQ]}
      {[Store].[USA].[CA].[Beverly Hills]}
      {[Store].[USA].[CA].[Beverly Hills].[Store 6]}
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[Los Angeles].[Store 7]}
      {[Store].[USA].[CA].[San Diego]}
      {[Store].[USA].[CA].[San Diego].[Store 24]}
      {[Store].[USA].[CA].[San Francisco]}
      {[Store].[USA].[CA].[San Francisco].[Store 14]}
      Row #0: 74,748
      Row #0: 74,748
      Row #0: 74,748
      Row #0:
      Row #0:
      Row #0: 21,333
      Row #0: 21,333
      Row #0: 25,663
      Row #0: 25,663
      Row #0: 25,635
      Row #0: 25,635
      Row #0: 2,117
      Row #0: 2,117
    RESULT
    cube = olap.raw_connection.getOlapSchema.getCubes.get("Sales")
    all_member = cube.lookupMember(
      Java::org.olap4j.mdx.IdentifierNode.parseIdentifier("[Store].[All Stores]").getSegmentList
    )
    refute_nil all_member
    assert_equal 1, all_member.getHierarchy.getRootMembers.size
    assert_equal "[Store].[All Stores]", all_member.getHierarchy.getRootMembers.get(0).getUniqueName
  end

  # MONDRIAN-1259: Mondrian security: access leaks from one user to another.
  # Enhancements to the SmartRestrictedMemberReader caused security leaks
  # between roles and possible class cast exceptions.
  # Java: AccessControlTest#testMondrian1259
  it "should not leak the access from one role to another" do
    mdx = "select non empty {[Store].Members} on columns from [Sales]"
    schema = foodmart_schema(role_defs: <<~'XML')
      <Role name="Role1">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="partial">
              <MemberGrant member="[Store].[USA].[CA]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role><Role name="Role2">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" access="custom" rollupPolicy="partial">
              <MemberGrant member="[Store].[USA].[OR]" access="all"/>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
    assert_query_returns(foodmart_connection(schema, role: 'Role1'), mdx, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Store].[All Stores]}
      {[Store].[USA]}
      {[Store].[USA].[CA]}
      {[Store].[USA].[CA].[Beverly Hills]}
      {[Store].[USA].[CA].[Beverly Hills].[Store 6]}
      {[Store].[USA].[CA].[Los Angeles]}
      {[Store].[USA].[CA].[Los Angeles].[Store 7]}
      {[Store].[USA].[CA].[San Diego]}
      {[Store].[USA].[CA].[San Diego].[Store 24]}
      {[Store].[USA].[CA].[San Francisco]}
      {[Store].[USA].[CA].[San Francisco].[Store 14]}
      Row #0: 74,748
      Row #0: 74,748
      Row #0: 74,748
      Row #0: 21,333
      Row #0: 21,333
      Row #0: 25,663
      Row #0: 25,663
      Row #0: 25,635
      Row #0: 25,635
      Row #0: 2,117
      Row #0: 2,117
    RESULT
    assert_query_returns(foodmart_connection(schema, role: 'Role2'), mdx, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Store].[All Stores]}
      {[Store].[USA]}
      {[Store].[USA].[OR]}
      {[Store].[USA].[OR].[Portland]}
      {[Store].[USA].[OR].[Portland].[Store 11]}
      {[Store].[USA].[OR].[Salem]}
      {[Store].[USA].[OR].[Salem].[Store 13]}
      Row #0: 67,659
      Row #0: 67,659
      Row #0: 67,659
      Row #0: 26,079
      Row #0: 26,079
      Row #0: 41,580
      Row #0: 41,580
    RESULT
  end

  # Java: AccessControlTest#testMondrian1295
  it "should apply the partial rollup policy in a native crossjoin of the time hierarchy" do
    mdx = <<~'MDX'
      With
      Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Time],[*BASE_MEMBERS_Product])'
      Set [*SORTED_ROW_AXIS] as 'Order([*CJ_ROW_AXIS],Ancestor([Time].CurrentMember, [Time].[Year]).OrderKey,BASC,Ancestor([Time].CurrentMember, [Time].[Quarter]).OrderKey,BASC,[Time].CurrentMember.OrderKey,BASC,[Product].CurrentMember.OrderKey,BASC)'
      Set [*BASE_MEMBERS_Product] as '{[Product].[All Products]}'
      Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}'
      Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Time].currentMember,[Product].currentMember)})'
      Set [*BASE_MEMBERS_Time] as '[Time].[Year].Members'
      Set [*CJ_COL_AXIS] as '[*NATIVE_CJ_SET]'
      Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=400
      Select
      [*BASE_MEMBERS_Measures] on columns,
      Non Empty [*SORTED_ROW_AXIS] on rows
      From [Sales]
    MDX

    schema = foodmart_schema(role_defs: <<~'XML')
      <Role name="Admin">
        <SchemaGrant access="none">
          <CubeGrant cube="Sales" access="all">
            <HierarchyGrant hierarchy="[Store]" rollupPolicy="partial" access="custom">
              <MemberGrant member="[Store].[USA].[CA]" access="all">
              </MemberGrant>
            </HierarchyGrant>
            <HierarchyGrant hierarchy="[Customers]" rollupPolicy="partial" access="custom">
              <MemberGrant member="[Customers].[USA].[CA]" access="all">
              </MemberGrant>
            </HierarchyGrant>
          </CubeGrant>
        </SchemaGrant>
      </Role>
    XML
    admin = foodmart_connection(schema, role: 'Admin')

    # Control
    assert_query_returns(foodmart_connection(schema), "select {[Measures].[Unit Sales]} on columns from [Sales]",
      <<~'RESULT')
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Row #0: 266,773
      RESULT
    assert_query_returns(admin, "select {[Measures].[Unit Sales]} on columns from [Sales]", <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales]}
      Row #0: 74,748
    RESULT

    # Test
    assert_query_returns(admin, mdx, <<~'RESULT')
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Time].[1997], [Product].[All Products]}
      Row #0: 74,748
    RESULT
  end

  # Java: AccessControlTest#testMondrian936
  it "should give the same value for an aggregate in the slicer and in a calculated member" do
    olap = role_connection(<<~'XML', 'test')
      <Role name="test">
       <SchemaGrant access="none">
         <CubeGrant cube="Sales" access="all">
           <HierarchyGrant hierarchy="[Store]" access="custom"
               topLevel="[Store].[Store Country]" rollupPolicy="partial">
             <MemberGrant member="[Store].[All Stores]" access="none"/>
             <MemberGrant member="[Store].[USA].[CA].[Los Angeles]" access="all"/>
             <MemberGrant member="[Store].[USA].[CA].[Alameda]" access="all"/>
             <MemberGrant member="[Store].[USA].[CA].[Beverly Hills]"
      access="all"/>
             <MemberGrant member="[Store].[USA].[CA].[San Francisco]"
      access="all"/>
             <MemberGrant member="[Store].[USA].[CA].[San Diego]" access="all"/>

             <MemberGrant member="[Store].[USA].[OR].[Portland]" access="all"/>
             <MemberGrant member="[Store].[USA].[OR].[Salem]" access="all"/>
           </HierarchyGrant>
         </CubeGrant>
       </SchemaGrant>
      </Role>
    XML

    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select {[Measures].[Unit Sales]} on columns,                  {[Product].[Food].[Baked Goods].[Bread]} on rows                  from [Sales]  where { [Store].[USA].[OR], [Store].[USA].[CA]}
    MDX
      Axis #0:
      {[Store].[USA].[OR]}
      {[Store].[USA].[CA]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Food].[Baked Goods].[Bread]}
      Row #0: 4,163
    RESULT

    # changing ordering of members in the slicer should not change
    # result
    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      select {[Measures].[Unit Sales]} on columns,                  {[Product].[Food].[Baked Goods].[Bread]} on rows                  from [Sales]  where { [Store].[USA].[CA], [Store].[USA].[OR]}
    MDX
      Axis #0:
      {[Store].[USA].[CA]}
      {[Store].[USA].[OR]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Food].[Baked Goods].[Bread]}
      Row #0: 4,163
    RESULT

    value_agg_member = olap.execute(
      "with member store.aggCaliforniaOregon as 'aggregate({ [Store].[USA].[CA], [Store].[USA].[OR]})'" \
      " select store.aggCaliforniaOregon on 0 from sales"
    ).raw_cell_set.getCell(0).getFormattedValue

    value_slicer_agg = olap.execute(
      " select from sales where { [Store].[USA].[CA], [Store].[USA].[OR]}"
    ).raw_cell_set.getCell(0).getFormattedValue

    # aggregating CA & OR in a calc member should produce same result
    # as aggregating in the slicer.
    assert_equal value_agg_member, value_slicer_agg
  end

  # Java: AccessControlTest#testMondrian1434
  it "should query a cube when the role restricts measures of another cube" do
    olap = role_connection(<<~'XML', 'dev')
      <Role name="dev">    <SchemaGrant access="all">      <CubeGrant cube="Sales" access="all">      </CubeGrant>      <CubeGrant cube="HR" access="all">      </CubeGrant>      <CubeGrant cube="Warehouse and Sales" access="all">         <HierarchyGrant hierarchy="Measures" access="custom">            <MemberGrant member="[Measures].[Warehouse Sales]" access="all">            </MemberGrant>         </HierarchyGrant>     </CubeGrant>  </SchemaGrant></Role>
    XML
    olap.execute(" select from [Sales] where {[Measures].[Unit Sales]}")

    olap = role_connection(<<~'XML', 'dev')
      <Role name="dev">    <SchemaGrant access="all">      <CubeGrant cube="Sales" access="all">         <HierarchyGrant hierarchy="Measures" access="custom">            <MemberGrant member="[Measures].[Unit Sales]" access="all">            </MemberGrant>         </HierarchyGrant>      </CubeGrant>      <CubeGrant cube="HR" access="all">      </CubeGrant>      <CubeGrant cube="Warehouse and Sales" access="all">     </CubeGrant>  </SchemaGrant></Role>
    XML
    olap.execute(" select from [Warehouse and Sales] where {[Measures].[Store Sales]}")
    # test is that there is no exception
  end

  # MONDRIAN-1486: with NECJ, RolapNativeCrossJoin.createEvaluator swapped the
  # LimitedRollupMember for the regular all member of the hierarchy, and
  # removed the security constraints.
  # Java: AccessControlTest#testMondrian1486
  it "should keep the limited rollup member in a native crossjoin evaluator" do
    olap = role_connection(<<~'XML', 'Admin')
      <Role name="Admin">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Gender]" rollupPolicy="partial" access="custom">
                <MemberGrant member="[Gender].[F]" access="all">
                </MemberGrant>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
    XML
    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      With
      Set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Gender],[*BASE_MEMBERS_Marital Status])'
      Set [*SORTED_ROW_AXIS] as 'Order([*CJ_ROW_AXIS],[Gender].CurrentMember.OrderKey,BASC,[Marital Status].CurrentMember.OrderKey,BASC)'
      Set [*BASE_MEMBERS_Gender] as '[Gender].[Gender].Members'
      Set [*BASE_MEMBERS_Measures] as '{[Measures].[*FORMATTED_MEASURE_0]}'
      Set [*CJ_ROW_AXIS] as 'Generate([*NATIVE_CJ_SET], {([Gender].currentMember,[Marital Status].currentMember)})'
      Set [*BASE_MEMBERS_Marital Status] as '[Marital Status].[Marital Status].Members'
      Set [*CJ_COL_AXIS] as '[*NATIVE_CJ_SET]'
      Member [Measures].[*FORMATTED_MEASURE_0] as '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=400
      Select
      [*BASE_MEMBERS_Measures] on columns,
      Non Empty [*SORTED_ROW_AXIS] on rows
      From [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Gender].[F], [Marital Status].[M]}
      {[Gender].[F], [Marital Status].[S]}
      Row #0: 65,336
      Row #1: 66,222
    RESULT
  end

  # The results are the same with all rollup policies, with a default member
  # that is not the all member, and with and without an all member.
  # MONDRIAN-1568 showed different results with different rollup policies and
  # different default members.
  # Java: AccessControlTest#testRollupPolicyWithNative
  it "should give the same native evaluation results with all rollup policies" do
    dimension = <<~'XML'
      <Dimension name="Store2">
        <Hierarchy hasAll="%s" primaryKey="store_id" %s >
          <Table name="store"/>
          <Level name="Store Country" column="store_country" uniqueMembers="true"/>
          <Level name="Store State" column="store_state" uniqueMembers="true"/>
        </Hierarchy>
      </Dimension>
    XML

    cube = <<~'XML'
      <Cube name="TinySales">
        <Table name="sales_fact_1997"/>
        <DimensionUsage name="Product" source="Product" foreignKey="product_id"/>
        <DimensionUsage name="Store2" source="Store2" foreignKey="store_id"/>
        <Measure name="Unit Sales" column="unit_sales" aggregator="sum"/>
      </Cube>
    XML

    role_defs = <<~'XML'
      <Role name="test">
              <SchemaGrant access="none">
                  <CubeGrant cube="TinySales" access="all">
                      <HierarchyGrant hierarchy="[Store2]" access="custom"
                                       rollupPolicy="%s">
                          <MemberGrant member="[Store2].[USA].[CA]" access="all"/>
                          <MemberGrant member="[Store2].[USA].[OR]" access="all"/>
                          <MemberGrant member="[Store2].[Canada]" access="all"/>
                      </HierarchyGrant>
                  </CubeGrant>
              </SchemaGrant>
          </Role>
    XML

    non_all_default_member = 'defaultMember="[Store2].[USA].[CA]"'

    with_mondrian_properties(NATIVE_PROPERTIES) do
      ROLLUP_POLICY.values.each do |policy|
        [non_all_default_member, ""].each do |default_member|
          [true, false].each do |has_all|
            olap = foodmart_connection(
              foodmart_schema(
                parameter_defs: format(dimension, has_all, default_member),
                cube_defs: cube,
                role_defs: format(role_defs, policy)
              ),
              role: 'test'
            )
            variant = "rollupPolicy=#{policy}, defaultMember=#{default_member}, hasAll=#{has_all}"
            # RolapNativeCrossjoin
            assert_like <<~'RESULT', format_result(olap.execute(<<~'MDX')), "Failure testing RolapNativeCrossJoin with #{variant}"
              Axis #0:
              {}
              Axis #1:
              {[Store2].[USA].[CA], [Product].[Drink]}
              {[Store2].[USA].[CA], [Product].[Food]}
              {[Store2].[USA].[CA], [Product].[Non-Consumable]}
              {[Store2].[USA].[OR], [Product].[Drink]}
              {[Store2].[USA].[OR], [Product].[Food]}
              {[Store2].[USA].[OR], [Product].[Non-Consumable]}
              Row #0: 7,102
              Row #0: 53,656
              Row #0: 13,990
              Row #0: 6,106
              Row #0: 48,537
              Row #0: 13,016
            RESULT
              select NonEmptyCrossJoin([Store2].[Store State].MEMBERS,[Product].[Product Family].MEMBERS) on 0 from tinysales
            MDX
            # RolapNativeFilter
            assert_like <<~'RESULT', format_result(olap.execute(<<~'MDX')), "Failure testing RolapNativeFilter with #{variant}"
              Axis #0:
              {}
              Axis #1:
              {[Measures].[Unit Sales]}
              Axis #2:
              {[Store2].[USA].[CA]}
              {[Store2].[USA].[OR]}
              Row #0: 74,748
              Row #1: 67,659
            RESULT
              select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
                Filter( [Store2].[USA].children,          [Measures].[Unit Sales]>0) ON ROWS
              from [TinySales]
            MDX
            # RolapNativeTopCount
            assert_like <<~'RESULT', format_result(olap.execute(<<~'MDX')), "Failure testing RolapNativeTopCount with #{variant}"
              Axis #0:
              {}
              Axis #1:
              {[Measures].[Unit Sales]}
              Axis #2:
              {[Store2].[USA].[CA]}
              {[Store2].[USA].[OR]}
              Row #0: 74,748
              Row #1: 67,659
            RESULT
              select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
                TopCount( [Store2].[USA].children,          2) ON ROWS
              from [TinySales]
            MDX
          end
        end
      end
    end
  end

  # MONDRIAN-1616
  # Java: AccessControlTest#testValidMeasureWithRestrictedCubes
  it "should give a valid measure of a base cube with no access" do
    olap = role_connection(<<~'XML', 'noBaseCubes')
      <Role name="noBaseCubes">
       <SchemaGrant access="all">
        <CubeGrant cube="Sales" access="none" />
        <CubeGrant cube="Sales Ragged" access="none" />
        <CubeGrant cube="Sales 2" access="none" />
        <CubeGrant cube="Warehouse" access="none" />
       </SchemaGrant>
      </Role>
    XML

    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      with member measures.vm as 'validmeasure(measures.[unit sales])' select measures.vm on 0 from [warehouse and sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[vm]}
      Row #0: 266,773
    RESULT

    assert_query_returns(olap, <<~'MDX', <<~'RESULT')
      with member measures.vm as 'validmeasure(measures.[warehouse cost])' select measures.vm * {gender.f} on 0 from [warehouse and sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[vm], [Gender].[F]}
      Row #0: 89,043.253
    RESULT
  end
end
