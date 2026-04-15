# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapNativeTopCountTest.java
describe "RolapNativeTopCountTest" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Creates a connection with an additional custom cube added to the schema.
  def connection_with_custom_cube(cube_xml)
    schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  # Creates a connection with a custom role added to the schema.
  def connection_with_role(role_xml, role_name)
    schema = SchemaHelper::FOODMART_SCHEMA.sub("</Schema>", "#{role_xml}</Schema>")
    params = CONNECTION_PARAMS.merge(catalog_content: schema, role: role_name)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  describe "TopCount with measures" do
    # Java: RolapNativeTopCountTest#testTopCount_ImplicitCountMeasure
    it "handles implicit count measure" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT [Measures].[Fact Count] ON COLUMNS, " \
          "TOPCOUNT([Store Type].[All Store Types].Children, 3, [Measures].[Fact Count]) ON ROWS " \
          "FROM [Store]",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Measures].[Fact Count]}
            Axis #2:
            {[Store Type].[Supermarket]}
            {[Store Type].[Deluxe Supermarket]}
            {[Store Type].[Mid-Size Grocery]}
            Row #0: 8
            Row #1: 6
            Row #2: 4
          RESULT
      end
    end

    # Java: RolapNativeTopCountTest#testTopCount_CountMeasure
    it "handles explicitly defined count measure" do
      cube_xml = <<~XML
        <Cube name="StoreWithCountM" visible="true" cache="true" enabled="true">
          <Table name="store">
          </Table>
          <Dimension visible="true" highCardinality="false" name="Store Type">
            <Hierarchy visible="true" hasAll="true">
              <Level name="Store Type" visible="true" column="store_type" type="String" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
              </Level>
            </Hierarchy>
          </Dimension>
          <DimensionUsage source="Store" name="Store" visible="true" highCardinality="false">
          </DimensionUsage>
          <Dimension visible="true" highCardinality="false" name="Has coffee bar">
            <Hierarchy visible="true" hasAll="true">
              <Level name="Has coffee bar" visible="true" column="coffee_bar" type="Boolean" uniqueMembers="true" levelType="Regular" hideMemberIf="Never">
              </Level>
            </Hierarchy>
          </Dimension>
          <Measure name="Store Sqft" column="store_sqft" formatString="#,###" aggregator="sum">
          </Measure>
          <Measure name="Grocery Sqft" column="grocery_sqft" formatString="#,###" aggregator="sum">
          </Measure>
          <Measure name="CountM" column="store_id" formatString="Standard" aggregator="count" visible="true">
          </Measure>
        </Cube>
      XML

      with_properties(EnableNativeTopCount: true) do
        olap = connection_with_custom_cube(cube_xml)
        begin
          assert_query_returns olap,
            "SELECT [Measures].[CountM] ON COLUMNS, " \
            "TOPCOUNT([Store Type].[All Store Types].Children, 3, [Measures].[CountM]) ON ROWS " \
            "FROM [StoreWithCountM]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Measures].[CountM]}
              Axis #2:
              {[Store Type].[Supermarket]}
              {[Store Type].[Deluxe Supermarket]}
              {[Store Type].[Mid-Size Grocery]}
              Row #0: 8
              Row #1: 6
              Row #2: 4
            RESULT
        ensure
          olap.close
        end
      end
    end

    # Java: RolapNativeTopCountTest#testTopCount_SumMeasure
    it "handles sum measure" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT [Measures].[Store Sqft] ON COLUMNS, " \
          "TOPCOUNT([Store Type].[All Store Types].Children, 3, [Measures].[Store Sqft]) ON ROWS " \
          "FROM [Store]",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Measures].[Store Sqft]}
            Axis #2:
            {[Store Type].[Supermarket]}
            {[Store Type].[Deluxe Supermarket]}
            {[Store Type].[Mid-Size Grocery]}
            Row #0: 193,480
            Row #1: 146,045
            Row #2: 109,343
          RESULT
      end
    end
  end

  describe "empty cells behavior" do
    # Java: RolapNativeTopCountTest#testEmptyCellsAreShown_Countries
    it "shows empty cells for countries" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
          "TOPCOUNT([Customers].[Country].Members, 2, [Measures].[Unit Sales]) ON ROWS " \
          "FROM [Sales] " \
          "WHERE [Time].[1997].[Q3]",
          <<~RESULT
            Axis #0:
            {[Time].[1997].[Q3]}
            Axis #1:
            {[Measures].[Unit Sales]}
            Axis #2:
            {[Customers].[USA]}
            {[Customers].[Canada]}
            Row #0: 65,848
            Row #1:#{' '}
          RESULT
      end
    end

    # Java: RolapNativeTopCountTest#testEmptyCellsAreShown_States
    it "shows empty cells for states" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
          "TOPCOUNT([Customers].[State Province].Members, 6, [Measures].[Unit Sales]) ON ROWS " \
          "FROM [Sales] " \
          "WHERE [Time].[1997].[Q3]",
          <<~RESULT
            Axis #0:
            {[Time].[1997].[Q3]}
            Axis #1:
            {[Measures].[Unit Sales]}
            Axis #2:
            {[Customers].[USA].[WA]}
            {[Customers].[USA].[CA]}
            {[Customers].[USA].[OR]}
            {[Customers].[Canada].[BC]}
            {[Customers].[Mexico].[DF]}
            {[Customers].[Mexico].[Guerrero]}
            Row #0: 30,538
            Row #1: 18,370
            Row #2: 16,940
            Row #3:#{' '}
            Row #4:#{' '}
            Row #5:#{' '}
          RESULT
      end
    end

    # Java: RolapNativeTopCountTest#testEmptyCellsAreShown_ButNoMoreThanReallyExist
    it "shows empty cells but no more than really exist" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
          "TOPCOUNT([Customers].[Country].Members, 10, [Measures].[Unit Sales]) ON ROWS " \
          "FROM [Sales] " \
          "WHERE [Time].[1997].[Q3]",
          <<~RESULT
            Axis #0:
            {[Time].[1997].[Q3]}
            Axis #1:
            {[Measures].[Unit Sales]}
            Axis #2:
            {[Customers].[USA]}
            {[Customers].[Canada]}
            {[Customers].[Mexico]}
            Row #0: 65,848
            Row #1:#{' '}
            Row #2:#{' '}
          RESULT
      end
    end

    # Java: RolapNativeTopCountTest#testEmptyCellsAreHidden_WhenNonEmptyIsDeclaredExplicitly
    it "hides empty cells when NON EMPTY is declared explicitly" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
          "NON EMPTY TOPCOUNT([Customers].[Country].Members, 2, [Measures].[Unit Sales]) ON ROWS " \
          "FROM [Sales] " \
          "WHERE [Time].[1997].[Q3]",
          <<~RESULT
            Axis #0:
            {[Time].[1997].[Q3]}
            Axis #1:
            {[Measures].[Unit Sales]}
            Axis #2:
            {[Customers].[USA]}
            Row #0: 65,848
          RESULT
      end
    end
  end

  describe "role restrictions" do
    # Java: RolapNativeTopCountTest#testRoleRestrictionWorks_ForRowWithData
    it "respects role restriction for row with data" do
      role_xml = <<~XML
        <Role name="No_WA_State">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="partial">
                <MemberGrant member="[Customers].[USA].[WA]" access="none"/>
                <MemberGrant member="[Customers].[USA].[OR]" access="all"/>
                <MemberGrant member="[Customers].[USA].[CA]" access="all"/>
                <MemberGrant member="[Customers].[Canada]" access="all"/>
                <MemberGrant member="[Customers].[Mexico]" access="all"/>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML

      with_properties(EnableNativeTopCount: true) do
        olap = connection_with_role(role_xml, "No_WA_State")
        begin
          assert_query_returns olap,
            "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
            "TOPCOUNT([Customers].[State Province].Members, 6, [Measures].[Unit Sales]) ON ROWS " \
            "FROM [Sales] " \
            "WHERE [Time].[1997].[Q3]",
            <<~RESULT
              Axis #0:
              {[Time].[1997].[Q3]}
              Axis #1:
              {[Measures].[Unit Sales]}
              Axis #2:
              {[Customers].[USA].[CA]}
              {[Customers].[USA].[OR]}
              {[Customers].[Canada].[BC]}
              {[Customers].[Mexico].[DF]}
              {[Customers].[Mexico].[Guerrero]}
              {[Customers].[Mexico].[Jalisco]}
              Row #0: 18,370
              Row #1: 16,940
              Row #2:#{' '}
              Row #3:#{' '}
              Row #4:#{' '}
              Row #5:#{' '}
            RESULT
        ensure
          olap.close
        end
      end
    end

    # Java: RolapNativeTopCountTest#testRoleRestrictionWorks_ForRowWithOutData
    it "respects role restriction for row without data" do
      role_xml = <<~XML
        <Role name="Only_DF_State">
          <SchemaGrant access="none">
            <CubeGrant cube="Sales" access="all">
              <HierarchyGrant hierarchy="[Customers]" access="custom" rollupPolicy="partial">
                <MemberGrant member="[Customers].[USA].[WA]" access="all"/>
                <MemberGrant member="[Customers].[USA].[OR]" access="all"/>
                <MemberGrant member="[Customers].[USA].[CA]" access="all"/>
                <MemberGrant member="[Customers].[Canada]" access="all"/>
                <MemberGrant member="[Customers].[Mexico].[DF]" access="all"/>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML

      with_properties(EnableNativeTopCount: true) do
        olap = connection_with_role(role_xml, "Only_DF_State")
        begin
          assert_query_returns olap,
            "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
            "TOPCOUNT([Customers].[State Province].Members, 6, [Measures].[Unit Sales]) ON ROWS " \
            "FROM [Sales] " \
            "WHERE [Time].[1997].[Q3]",
            <<~RESULT
              Axis #0:
              {[Time].[1997].[Q3]}
              Axis #1:
              {[Measures].[Unit Sales]}
              Axis #2:
              {[Customers].[USA].[WA]}
              {[Customers].[USA].[CA]}
              {[Customers].[USA].[OR]}
              {[Customers].[Canada].[BC]}
              {[Customers].[Mexico].[DF]}
              Row #0: 30,538
              Row #1: 18,370
              Row #2: 16,940
              Row #3:#{' '}
              Row #4:#{' '}
            RESULT
        ensure
          olap.close
        end
      end
    end
  end

  describe "TopCount mimics HEAD with two params" do
    # Java: RolapNativeTopCountTest#testMimicsHeadWhenTwoParams_States
    it "mimics HEAD for states" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT TOPCOUNT([Customers].[State Province].members, 3) ON COLUMNS " \
          "FROM [Sales] ",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Customers].[Canada].[BC]}
            {[Customers].[Mexico].[DF]}
            {[Customers].[Mexico].[Guerrero]}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
          RESULT
      end
    end

    # Java: RolapNativeTopCountTest#testMimicsHeadWhenTwoParams_Cities
    it "mimics HEAD for cities" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT TOPCOUNT([Customers].[City].members, 30) ON COLUMNS " \
          "FROM [Sales] ",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Customers].[Canada].[BC].[Burnaby]}
            {[Customers].[Canada].[BC].[Cliffside]}
            {[Customers].[Canada].[BC].[Haney]}
            {[Customers].[Canada].[BC].[Ladner]}
            {[Customers].[Canada].[BC].[Langford]}
            {[Customers].[Canada].[BC].[Langley]}
            {[Customers].[Canada].[BC].[Metchosin]}
            {[Customers].[Canada].[BC].[N. Vancouver]}
            {[Customers].[Canada].[BC].[Newton]}
            {[Customers].[Canada].[BC].[Oak Bay]}
            {[Customers].[Canada].[BC].[Port Hammond]}
            {[Customers].[Canada].[BC].[Richmond]}
            {[Customers].[Canada].[BC].[Royal Oak]}
            {[Customers].[Canada].[BC].[Shawnee]}
            {[Customers].[Canada].[BC].[Sooke]}
            {[Customers].[Canada].[BC].[Vancouver]}
            {[Customers].[Canada].[BC].[Victoria]}
            {[Customers].[Canada].[BC].[Westminster]}
            {[Customers].[Mexico].[DF].[San Andres]}
            {[Customers].[Mexico].[DF].[Santa Anita]}
            {[Customers].[Mexico].[DF].[Santa Fe]}
            {[Customers].[Mexico].[DF].[Tixapan]}
            {[Customers].[Mexico].[Guerrero].[Acapulco]}
            {[Customers].[Mexico].[Jalisco].[Guadalajara]}
            {[Customers].[Mexico].[Mexico].[Mexico City]}
            {[Customers].[Mexico].[Oaxaca].[Tlaxiaco]}
            {[Customers].[Mexico].[Sinaloa].[La Cruz]}
            {[Customers].[Mexico].[Veracruz].[Orizaba]}
            {[Customers].[Mexico].[Yucatan].[Merida]}
            {[Customers].[Mexico].[Zacatecas].[Camacho]}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0:#{' '}
          RESULT
      end
    end

    # Java: RolapNativeTopCountTest#testMimicsHeadWhenTwoParams_ShowsNotMoreThanExist
    it "shows no more results than exist with two params" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT TOPCOUNT([Customers].[Country].members, 5) ON COLUMNS " \
          "FROM [Sales] ",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Customers].[Canada]}
            {[Customers].[Mexico]}
            {[Customers].[USA]}
            Row #0:#{' '}
            Row #0:#{' '}
            Row #0: 266,773
          RESULT
      end
    end

    # Java: RolapNativeTopCountTest#testMimicsHeadWhenTwoParams_DoesNotIgnoreNonEmpty
    it "does not ignore NON EMPTY with two params" do
      with_properties(EnableNativeTopCount: true) do
        assert_query_returns @olap,
          "SELECT NON EMPTY TOPCOUNT([Customers].[State Province].members, 3) ON COLUMNS " \
          "FROM [Sales] ",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
          RESULT
      end
    end
  end
end
