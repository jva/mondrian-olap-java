# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2005-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/SharedDimensionTest.java
describe "SharedDimension" do
  SHARED_DIMENSION = <<~XML
    <Dimension name="Employee">
      <Hierarchy hasAll="true" primaryKey="employee_id" primaryKeyTable="employee">
        <Join leftKey="supervisor_id" rightKey="employee_id">
          <Table name="employee" alias="employee" />
          <Table name="employee" alias="employee_manager" />
        </Join>
        <Level name="Role" table="employee_manager" column="management_role" uniqueMembers="true"/>
        <Level name="Title" table="employee_manager" column="position_title" uniqueMembers="false"/>
      </Hierarchy>
    </Dimension>
  XML

  # Base Cube A: use product_id as foreign key for Employee dimension
  # because there exist rows satisfying the join condition
  # "employee.employee_id = inventory_fact_1997.product_id"
  CUBE_A = <<~XML
    <Cube name="Employee Store Analysis A">
      <Table name="inventory_fact_1997" alias="inventory" />
      <DimensionUsage name="Employee" source="Employee" foreignKey="product_id" />
      <DimensionUsage name="Store Type" source="Store Type" foreignKey="warehouse_id" />
      <Measure name="Employee Store Sales" aggregator="sum" formatString="$#,##0" column="warehouse_sales" />
      <Measure name="Employee Store Cost" aggregator="sum" formatString="$#,##0" column="warehouse_cost" />
    </Cube>
  XML

  # Base Cube B: use time_id as foreign key for Employee dimension
  # because there exist rows satisfying the join condition
  # "employee.employee_id = inventory_fact_1997.time_id"
  CUBE_B = <<~XML
    <Cube name="Employee Store Analysis B">
      <Table name="inventory_fact_1997" alias="inventory" />
      <DimensionUsage name="Employee" source="Employee" foreignKey="time_id" />
      <DimensionUsage name="Store Type" source="Store Type" foreignKey="store_id" />
      <Measure name="Employee Store Sales" aggregator="sum" formatString="$#,##0" column="warehouse_sales" />
      <Measure name="Employee Store Cost" aggregator="sum" formatString="$#,##0" column="warehouse_cost" />
    </Cube>
  XML

  # Some product_id's match store_id. Used to test MONDRIAN-1243
  # without having to alter fact table.
  CUBE_ALT_SALES = <<~XML
    <Cube name="Alternate Sales">
      <Table name="sales_fact_1997"/>
      <DimensionUsage name="Store Type" source="Store Type" foreignKey="store_id" />
      <DimensionUsage name="Store" source="Store" foreignKey="store_id"/>
      <DimensionUsage name="Buyer" source="Store" visible="true" foreignKey="product_id" highCardinality="false"/>
      <DimensionUsage name="BuyerTwo" source="Store" visible="true" foreignKey="product_id" highCardinality="false"/>
      <DimensionUsage name="Store Size in SQFT" source="Store Size in SQFT"
          foreignKey="store_id"/>
      <DimensionUsage name="Store Type" source="Store Type" foreignKey="store_id"/>
      <DimensionUsage name="Time" source="Time" foreignKey="time_id"/>
      <Measure name="Unit Sales" column="unit_sales" aggregator="sum" formatString="Standard"/>
    </Cube>
  XML

  VIRTUAL_CUBE = <<~XML
    <VirtualCube name="Employee Store Analysis">
      <VirtualCubeDimension name="Employee"/>
      <VirtualCubeDimension name="Store Type"/>
      <VirtualCubeMeasure cubeName="Employee Store Analysis A" name="[Measures].[Employee Store Sales]"/>
      <VirtualCubeMeasure cubeName="Employee Store Analysis B" name="[Measures].[Employee Store Cost]"/>
    </VirtualCube>
  XML

  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Create a connection with the shared Employee dimension and cubes A and B.
  # Java: getTestContextForSharedDimCubeACubeB
  def connection_with_cubes_a_and_b
    schema = SchemaHelper::FOODMART_SCHEMA.dup
    schema = schema.sub("<Cube", "#{SHARED_DIMENSION}<Cube")
    schema = schema.sub("<VirtualCube", "#{CUBE_A}#{CUBE_B}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  # Create a connection with the shared Employee dimension, cubes A and B,
  # and a virtual cube built over them.
  def connection_with_virtual_cube
    schema = SchemaHelper::FOODMART_SCHEMA.dup
    schema = schema.sub("<Cube", "#{SHARED_DIMENSION}<Cube")
    schema = schema.sub("<VirtualCube", "#{CUBE_A}#{CUBE_B}<VirtualCube")
    schema = schema.sub("<Role", "#{VIRTUAL_CUBE}<Role")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  # Create a connection with the Alternate Sales cube.
  # Java: getTestContextForSharedDimCubeAltSales
  def connection_with_alt_sales
    schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{CUBE_ALT_SALES}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  # Schema has two cubes sharing a dimension.
  # Query from the first cube.
  # Java: SharedDimensionTest#testA
  it "query from cube A with shared dimension" do
    olap = connection_with_cubes_a_and_b
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        with
          set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Employee], [*BASE_MEMBERS_Store Type])'
          set [*BASE_MEMBERS_Measures] as '{[Measures].[Employee Store Sales], [Measures].[Employee Store Cost]}'
          set [*BASE_MEMBERS_Employee] as '[Employee].[Role].Members'
          set [*NATIVE_MEMBERS_Employee] as 'Generate([*NATIVE_CJ_SET], {[Employee].CurrentMember})'
          set [*BASE_MEMBERS_Store Type] as '[Store Type].[Store Type].Members'
          set [*NATIVE_MEMBERS_Store Type] as 'Generate([*NATIVE_CJ_SET], {[Store Type].CurrentMember})'
        select
          [*BASE_MEMBERS_Measures] ON COLUMNS,
          NON EMPTY Generate([*NATIVE_CJ_SET], {([Employee].CurrentMember, [Store Type].CurrentMember)}) ON ROWS
        from
          [Employee Store Analysis A]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Employee Store Sales]}
        {[Measures].[Employee Store Cost]}
        Axis #2:
        {[Employee].[Middle Management], [Store Type].[Deluxe Supermarket]}
        {[Employee].[Middle Management], [Store Type].[Supermarket]}
        {[Employee].[Senior Management], [Store Type].[Deluxe Supermarket]}
        {[Employee].[Senior Management], [Store Type].[Gourmet Supermarket]}
        {[Employee].[Senior Management], [Store Type].[Mid-Size Grocery]}
        {[Employee].[Senior Management], [Store Type].[Small Grocery]}
        {[Employee].[Senior Management], [Store Type].[Supermarket]}
        {[Employee].[Store Management], [Store Type].[Deluxe Supermarket]}
        {[Employee].[Store Management], [Store Type].[Gourmet Supermarket]}
        {[Employee].[Store Management], [Store Type].[Mid-Size Grocery]}
        {[Employee].[Store Management], [Store Type].[Small Grocery]}
        {[Employee].[Store Management], [Store Type].[Supermarket]}
        Row #0: $200
        Row #0: $87
        Row #1: $161
        Row #1: $68
        Row #2: $1,721
        Row #2: $739
        Row #3: $261
        Row #3: $114
        Row #4: $257
        Row #4: $111
        Row #5: $196
        Row #5: $101
        Row #6: $3,993
        Row #6: $1,858
        Row #7: $45,014
        Row #7: $20,604
        Row #8: $7,231
        Row #8: $3,211
        Row #9: $8,171
        Row #9: $3,635
        Row #10: $4,471
        Row #10: $2,045
        Row #11: $77,236
        Row #11: $34,842
      RESULT
    ensure
      olap.close
    end
  end

  # Schema has two cubes sharing a dimension.
  # Query from the second cube.
  # Java: SharedDimensionTest#testB
  it "query from cube B with shared dimension" do
    olap = connection_with_cubes_a_and_b
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        with
          set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Employee], [*BASE_MEMBERS_Store Type])'
          set [*BASE_MEMBERS_Measures] as '{[Measures].[Employee Store Sales], [Measures].[Employee Store Cost]}'
          set [*BASE_MEMBERS_Employee] as '[Employee].[Role].Members'
          set [*NATIVE_MEMBERS_Employee] as 'Generate([*NATIVE_CJ_SET], {[Employee].CurrentMember})'
          set [*BASE_MEMBERS_Store Type] as '[Store Type].[Store Type].Members'
          set [*NATIVE_MEMBERS_Store Type] as 'Generate([*NATIVE_CJ_SET], {[Store Type].CurrentMember})'
        select
          [*BASE_MEMBERS_Measures] ON COLUMNS,
          NON EMPTY Generate([*NATIVE_CJ_SET], {([Employee].CurrentMember, [Store Type].CurrentMember)}) ON ROWS
        from
          [Employee Store Analysis B]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Employee Store Sales]}
        {[Measures].[Employee Store Cost]}
        Axis #2:
        {[Employee].[Store Management], [Store Type].[Deluxe Supermarket]}
        {[Employee].[Store Management], [Store Type].[Gourmet Supermarket]}
        {[Employee].[Store Management], [Store Type].[Mid-Size Grocery]}
        {[Employee].[Store Management], [Store Type].[Small Grocery]}
        {[Employee].[Store Management], [Store Type].[Supermarket]}
        Row #0: $61,860
        Row #0: $28,093
        Row #1: $10,156
        Row #1: $4,482
        Row #2: $10,212
        Row #2: $4,576
        Row #3: $5,932
        Row #3: $2,714
        Row #4: $108,610
        Row #4: $49,178
      RESULT
    ensure
      olap.close
    end
  end

  # Schema has two cubes sharing a dimension, and a virtual cube built
  # over these two cubes.
  # Query from the virtual cube.
  # Java: SharedDimensionTest#testVirtualCube
  it "query from virtual cube with shared dimension" do
    olap = connection_with_virtual_cube
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        with
          set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Employee], [*BASE_MEMBERS_Store Type])'
          set [*BASE_MEMBERS_Measures] as '{[Measures].[Employee Store Sales], [Measures].[Employee Store Cost]}'
          set [*BASE_MEMBERS_Employee] as '[Employee].[Role].Members'
          set [*NATIVE_MEMBERS_Employee] as 'Generate([*NATIVE_CJ_SET], {[Employee].CurrentMember})'
          set [*BASE_MEMBERS_Store Type] as '[Store Type].[Store Type].Members'
          set [*NATIVE_MEMBERS_Store Type] as 'Generate([*NATIVE_CJ_SET], {[Store Type].CurrentMember})'
        select
          [*BASE_MEMBERS_Measures] ON COLUMNS,
          NON EMPTY Generate([*NATIVE_CJ_SET], {([Employee].CurrentMember, [Store Type].CurrentMember)}) ON ROWS
        from
          [Employee Store Analysis]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Employee Store Sales]}
        {[Measures].[Employee Store Cost]}
        Axis #2:
        {[Employee].[Middle Management], [Store Type].[Deluxe Supermarket]}
        {[Employee].[Middle Management], [Store Type].[Supermarket]}
        {[Employee].[Senior Management], [Store Type].[Deluxe Supermarket]}
        {[Employee].[Senior Management], [Store Type].[Gourmet Supermarket]}
        {[Employee].[Senior Management], [Store Type].[Mid-Size Grocery]}
        {[Employee].[Senior Management], [Store Type].[Small Grocery]}
        {[Employee].[Senior Management], [Store Type].[Supermarket]}
        {[Employee].[Store Management], [Store Type].[Deluxe Supermarket]}
        {[Employee].[Store Management], [Store Type].[Gourmet Supermarket]}
        {[Employee].[Store Management], [Store Type].[Mid-Size Grocery]}
        {[Employee].[Store Management], [Store Type].[Small Grocery]}
        {[Employee].[Store Management], [Store Type].[Supermarket]}
        Row #0: $200
        Row #0:
        Row #1: $161
        Row #1:
        Row #2: $1,721
        Row #2:
        Row #3: $261
        Row #3:
        Row #4: $257
        Row #4:
        Row #5: $196
        Row #5:
        Row #6: $3,993
        Row #6:
        Row #7: $45,014
        Row #7: $28,093
        Row #8: $7,231
        Row #8: $4,482
        Row #9: $8,171
        Row #9: $4,576
        Row #10: $4,471
        Row #10: $2,714
        Row #11: $77,236
        Row #11: $49,178
      RESULT
    ensure
      olap.close
    end
  end

  # Schema has two cubes sharing a dimension.
  # Query from the second cube with NECJ member list.
  # Java: SharedDimensionTest#testNECJMemberList
  it "NECJ member list with shared dimension" do
    olap = connection_with_cubes_a_and_b
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        select {[Measures].[Employee Store Sales]} on columns,
        NonEmptyCrossJoin([Store Type].[Store Type].Members,
        {[Employee].[All Employees].[Middle Management],
         [Employee].[All Employees].[Store Management]})
        on rows from [Employee Store Analysis B]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Employee Store Sales]}
        Axis #2:
        {[Store Type].[Deluxe Supermarket], [Employee].[Store Management]}
        {[Store Type].[Gourmet Supermarket], [Employee].[Store Management]}
        {[Store Type].[Mid-Size Grocery], [Employee].[Store Management]}
        {[Store Type].[Small Grocery], [Employee].[Store Management]}
        {[Store Type].[Supermarket], [Employee].[Store Management]}
        Row #0: $61,860
        Row #1: $10,156
        Row #2: $10,212
        Row #3: $5,932
        Row #4: $108,610
      RESULT
    ensure
      olap.close
    end
  end

  # Schema has two cubes sharing a dimension.
  # Query from the first cube.
  # This is a case where not using alias not only affects performance,
  # but also produces incorrect result.
  # Java: SharedDimensionTest#testNECJMultiLevelMemberList
  it "NECJ multi-level member list with shared dimension" do
    olap = connection_with_cubes_a_and_b
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        select {[Employee Store Sales]} on columns, NonEmptyCrossJoin([Store Type].[Store Type].Members, {[Employee].[Store Management].[Store Manager], [Employee].[Senior Management].[President]}) on rows from [Employee Store Analysis B]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Employee Store Sales]}
        Axis #2:
        {[Store Type].[Deluxe Supermarket], [Employee].[Store Management].[Store Manager]}
        {[Store Type].[Gourmet Supermarket], [Employee].[Store Management].[Store Manager]}
        {[Store Type].[Supermarket], [Employee].[Store Management].[Store Manager]}
        Row #0: $1,783
        Row #1: $286
        Row #2: $1,020
      RESULT
    ensure
      olap.close
    end
  end

  # Test case for MONDRIAN-286, "NullPointerException for certain mdx
  # using [Sales 2]".
  # Uses the default FoodMart schema.
  # Java: SharedDimensionTest#testBugMondrian286
  it "bug MONDRIAN-286 NullPointerException for Sales 2" do
    assert_query_returns @olap,
      "select NON EMPTY {[Product].[Product Family].Members} ON COLUMNS from [Sales 2]",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Product].[Drink]}
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        Row #0: 7,978
        Row #0: 62,445
        Row #0: 16,414
      RESULT
  end

  # Uses the default FoodMart schema.
  # This result is actually incorrect for native evaluation.
  # Keep the test case here to test the SQL generation.
  # Java: SharedDimensionTest#testStoreCube
  it "query from Store cube with Store Type dimension" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with set [*NATIVE_CJ_SET] as 'NonEmptyCrossJoin([*BASE_MEMBERS_Store Type], [*BASE_MEMBERS_Store])'
      set [*BASE_MEMBERS_Measures] as '{[Measures].[Store Sqft]}'
      set [*BASE_MEMBERS_Store Type] as '[Store Type].[Store Type].Members'
      set [*BASE_MEMBERS_Store] as '[Store].[Store State].Members'
      select [*BASE_MEMBERS_Measures] ON COLUMNS,
      Non Empty Generate([*NATIVE_CJ_SET], {[Store Type].CurrentMember}) on rows from [Store]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Store Sqft]}
      Axis #2:
      {[Store Type].[Deluxe Supermarket]}
      {[Store Type].[Gourmet Supermarket]}
      {[Store Type].[Mid-Size Grocery]}
      {[Store Type].[Small Grocery]}
      {[Store Type].[Supermarket]}
      Row #0: 146,045
      Row #1: 47,447
      Row #2: 109,343
      Row #3: 75,281
      Row #4: 193,480
    RESULT
  end

  # Test case for MONDRIAN-1243, "Wrong table alias in SQL generated to
  # populate member cache".
  # Java: SharedDimensionTest#testBugMondrian1243WrongAlias
  it "bug MONDRIAN-1243 wrong table alias with shared dimension" do
    olap = connection_with_alt_sales
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        select [Measures].[Unit Sales] on columns,
        non empty [Buyer].[USA].[OR].[Portland].children on rows
        from [Alternate Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Buyer].[USA].[OR].[Portland].[Store 11]}
        Row #0: 238
      RESULT
    ensure
      olap.close
    end
  end

  # Java: SharedDimensionTest#testMemberUniqueNameForSharedWithChangedName
  it "member unique name for shared dimension with changed name" do
    olap = connection_with_alt_sales
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        with
         member [BuyerTwo].[Mexico].[calc] as '[BuyerTwo].[Mexico]'
        select [BuyerTwo].[Mexico].[calc] on 0 from [Alternate Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[BuyerTwo].[Mexico].[calc]}
        Row #0: 1,389
      RESULT
    ensure
      olap.close
    end
  end
end
