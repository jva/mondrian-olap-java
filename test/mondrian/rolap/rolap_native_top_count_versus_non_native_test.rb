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

# Java: mondrian/rolap/RolapNativeTopCountVersusNonNativeTest.java
describe "RolapNativeTopCountVersusNonNativeTest" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Checks whether query produces the same results with the native.* props
  # enabled as it does with the props disabled.
  # Matches Java BatchTestCase.verifySameNativeAndNot.
  def verify_same_native_and_not(mdx, connection: @olap)
    with_properties(
      EnableNativeCrossJoin: true,
      EnableNativeFilter: true,
      EnableNativeNonEmpty: true,
      EnableNativeTopCount: true
    ) do
      result_native = format_result(connection.execute(mdx))

      with_properties(
        EnableNativeCrossJoin: false,
        EnableNativeFilter: false,
        EnableNativeNonEmpty: false,
        EnableNativeTopCount: false
      ) do
        result_non_native = format_result(connection.execute(mdx))
        assert_equal result_native, result_non_native
      end
    end
  end

  # Java: RolapNativeTopCountVersusNonNativeTest#testTopCount_ImplicitCountMeasure
  it "implicit count measure" do
    mdx = "SELECT [Measures].[Fact Count] ON COLUMNS, " \
          "TOPCOUNT([Store Type].[All Store Types].Children, 3, [Measures].[Fact Count]) ON ROWS " \
          "FROM [Store]"
    verify_same_native_and_not(mdx)
  end

  # Java: RolapNativeTopCountVersusNonNativeTest#testTopCount_SumMeasure
  it "sum measure" do
    mdx = "SELECT [Measures].[Store Sqft] ON COLUMNS, " \
          "TOPCOUNT([Store Type].[All Store Types].Children, 3, [Measures].[Store Sqft]) ON ROWS " \
          "FROM [Store]"
    verify_same_native_and_not(mdx)
  end

  # Java: RolapNativeTopCountVersusNonNativeTest#testTopCount_CountMeasure
  it "custom count measure" do
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

    schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    connection = Mondrian::OLAP::Connection.create(params)
    begin
      mdx = "SELECT [Measures].[CountM] ON COLUMNS, " \
            "TOPCOUNT([Store Type].[All Store Types].Children, 3, [Measures].[CountM]) ON ROWS " \
            "FROM [StoreWithCountM]"
      verify_same_native_and_not(mdx, connection: connection)
    ensure
      connection.close
    end
  end

  # Java: RolapNativeTopCountVersusNonNativeTest#testEmptyCellsAreShown_Countries
  it "empty cells are shown - countries" do
    mdx = "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
          "TOPCOUNT([Customers].[Country].Members, 2, [Measures].[Unit Sales]) ON ROWS " \
          "FROM [Sales] " \
          "WHERE [Time].[1997].[Q3]"
    verify_same_native_and_not(mdx)
  end

  # Java: RolapNativeTopCountVersusNonNativeTest#testEmptyCellsAreShown_States
  it "empty cells are shown - states" do
    mdx = "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
          "TOPCOUNT([Customers].[State Province].Members, 6, [Measures].[Unit Sales]) ON ROWS " \
          "FROM [Sales] " \
          "WHERE [Time].[1997].[Q3]"
    verify_same_native_and_not(mdx)
  end

  # No extra lines are returned even if limit is larger than the number of members.
  # Java: RolapNativeTopCountVersusNonNativeTest#testEmptyCellsAreShown_ButNoMoreThanReallyExist
  it "empty cells are shown - but no more than really exist" do
    mdx = "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
          "TOPCOUNT([Customers].[Country].Members, 10, [Measures].[Unit Sales]) ON ROWS " \
          "FROM [Sales] " \
          "WHERE [Time].[1997].[Q3]"
    verify_same_native_and_not(mdx)
  end

  # Java: RolapNativeTopCountVersusNonNativeTest#testEmptyCellsAreHidden_WhenNonEmptyIsDeclaredExplicitly
  it "empty cells are hidden when NON EMPTY is declared explicitly" do
    mdx = "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
          "NON EMPTY TOPCOUNT([Customers].[Country].Members, 2, [Measures].[Unit Sales]) ON ROWS " \
          "FROM [Sales] " \
          "WHERE [Time].[1997].[Q3]"
    verify_same_native_and_not(mdx)
  end

  # Role restriction works for rows with data ([USA].[WA] has 30538).
  # Java: RolapNativeTopCountVersusNonNativeTest#testRoleRestrictionWorks_ForRowWithData
  it "role restriction works - for row with data" do
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

    schema = SchemaHelper::FOODMART_SCHEMA.sub("</Schema>", "#{role_xml}\n</Schema>")
    params = CONNECTION_PARAMS.merge(catalog_content: schema, role: "No_WA_State")
    params.delete(:catalog)
    connection = Mondrian::OLAP::Connection.create(params)
    begin
      mdx = "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
            "TOPCOUNT([Customers].[State Province].Members, 6, [Measures].[Unit Sales]) ON ROWS " \
            "FROM [Sales] " \
            "WHERE [Time].[1997].[Q3]"
      verify_same_native_and_not(mdx, connection: connection)
    ensure
      connection.close
    end
  end

  # Role restriction works for rows without data:
  # only [Mexico].[DF] is visible among [Mexico].Children.
  # Java: RolapNativeTopCountVersusNonNativeTest#testRoleRestrictionWorks_ForRowWithOutData
  it "role restriction works - for row without data" do
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

    schema = SchemaHelper::FOODMART_SCHEMA.sub("</Schema>", "#{role_xml}\n</Schema>")
    params = CONNECTION_PARAMS.merge(catalog_content: schema, role: "Only_DF_State")
    params.delete(:catalog)
    connection = Mondrian::OLAP::Connection.create(params)
    begin
      mdx = "SELECT [Measures].[Unit Sales] ON COLUMNS, " \
            "TOPCOUNT([Customers].[State Province].Members, 6, [Measures].[Unit Sales]) ON ROWS " \
            "FROM [Sales] " \
            "WHERE [Time].[1997].[Q3]"
      verify_same_native_and_not(mdx, connection: connection)
    ensure
      connection.close
    end
  end

  # TopCount mimics HEAD's behaviour for states level.
  # Java: RolapNativeTopCountVersusNonNativeTest#testMimicsHeadWhenTwoParams_States
  it "mimics head when two params - states" do
    mdx = "SELECT TOPCOUNT([Customers].[State Province].members, 3) ON COLUMNS " \
          "FROM [Sales] "
    verify_same_native_and_not(mdx)
  end

  # TopCount mimics HEAD's behaviour for cities level.
  # Java: RolapNativeTopCountVersusNonNativeTest#testMimicsHeadWhenTwoParams_Cities
  it "mimics head when two params - cities" do
    mdx = "SELECT TOPCOUNT([Customers].[City].members, 30) ON COLUMNS " \
          "FROM [Sales] "
    verify_same_native_and_not(mdx)
  end

  # No extra lines are returned even if limit is larger than the number of members.
  # Java: RolapNativeTopCountVersusNonNativeTest#testMimicsHeadWhenTwoParams_ShowsNotMoreThanExist
  it "mimics head when two params - shows not more than exist" do
    mdx = "SELECT TOPCOUNT([Customers].[Country].members, 5) ON COLUMNS " \
          "FROM [Sales] "
    verify_same_native_and_not(mdx)
  end

  # NON EMPTY modifier is not neglected when only two parameters are used.
  # Java: RolapNativeTopCountVersusNonNativeTest#testMimicsHeadWhenTwoParams_DoesNotIgnoreNonEmpty
  it "mimics head when two params - does not ignore NON EMPTY" do
    mdx = "SELECT NON EMPTY TOPCOUNT([Customers].[State Province].members, 3) ON COLUMNS " \
          "FROM [Sales] "
    verify_same_native_and_not(mdx)
  end
end
