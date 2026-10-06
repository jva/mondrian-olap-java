# frozen_string_literal: true

require_relative "../../../test_helper"

describe "CrossJoin" do
  # When invalid members are ignored, an invalid measure resolves to the null
  # member of the Measures hierarchy. NonEmptyCrossJoin checks each tuple with
  # the measures that the calculated measures refer to, so the null measure must
  # not be one of them.
  describe "NonEmptyCrossJoin with an invalid measure" do
    before(:all) do
      role_xml = <<~XML
        <Role name="Female only">
          <SchemaGrant access="none">
            <CubeGrant cube="Warehouse and Sales" access="all">
              <HierarchyGrant hierarchy="[Gender]" access="custom" rollupPolicy="partial">
                <MemberGrant member="[Gender].[F]" access="all"/>
              </HierarchyGrant>
            </CubeGrant>
          </SchemaGrant>
        </Role>
      XML
      calculated_member_xml = <<~XML
        <CalculatedMember name="Schema invalid reference" dimension="Measures">
          <Formula>[Measures].[Unit Sales] + [Measures].[Not existing measure]</Formula>
        </CalculatedMember>
      XML
      catalog_xml = File.read(CATALOG_FILE)
        .sub("</VirtualCube>", "#{calculated_member_xml}</VirtualCube>")
        .sub("</Schema>", "#{role_xml}</Schema>")

      ignore_invalid_members = Java::MondrianOlap::MondrianProperties.instance.IgnoreInvalidMembers
      original_ignore_invalid_members = ignore_invalid_members.get
      ignore_invalid_members.set(true)
      begin
        @role_olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS.except(:catalog).merge(catalog_content: catalog_xml))
      ensure
        ignore_invalid_members.set(original_ignore_invalid_members)
      end
    end

    after(:all) do
      @role_olap&.close
    end

    around do |&block|
      property = Java::MondrianOlap::MondrianProperties.instance.IgnoreInvalidMembersDuringQuery
      original = property.get
      property.set(true)
      begin
        super(&block)
      ensure
        property.set(original)
      end
    end

    after do
      @role_olap.role_name = nil
    end

    # A partial rollup role replaces the All member of [Gender] with a member
    # whose value is an Aggregate over the visible children. That Aggregate
    # needs a stored measure in the context of a virtual cube.
    it "evaluates a measure that refers to an invalid measure with a partial rollup role" do
      @role_olap.role_name = "Female only"
      result = @role_olap.execute <<~MDX
        WITH MEMBER [Measures].[Invalid reference] AS
          [Measures].[Unit Sales] + [Measures].[Not existing measure]
        SELECT {[Measures].[Unit Sales], [Measures].[Invalid reference]} ON COLUMNS,
          NonEmptyCrossJoin({[Product].[All Products], [Product].[Drink]}, {[Store].[All Stores]}) ON ROWS
        FROM [Warehouse and Sales]
      MDX

      assert_equal [[131_558, 131_558], [12_202, 12_202]], result.values
    end

    it "evaluates a measure that refers to an invalid measure through another calculated measure" do
      @role_olap.role_name = "Female only"
      result = @role_olap.execute <<~MDX
        WITH MEMBER [Measures].[Invalid reference] AS
          [Measures].[Unit Sales] + [Measures].[Not existing measure]
        MEMBER [Measures].[Outer reference] AS [Measures].[Invalid reference] * 2
        SELECT {[Measures].[Outer reference]} ON COLUMNS,
          NonEmptyCrossJoin({[Product].[All Products], [Product].[Drink]}, {[Store].[All Stores]}) ON ROWS
        FROM [Warehouse and Sales]
      MDX

      assert_equal [[263_116], [24_404]], result.values
    end

    # The query does not refer to the invalid measure, so only the visitor of
    # the calculated measure expressions finds it.
    it "evaluates a schema calculated measure that refers to an invalid measure" do
      @role_olap.role_name = "Female only"
      result = @role_olap.execute <<~MDX
        SELECT {[Measures].[Schema invalid reference]} ON COLUMNS,
          NonEmptyCrossJoin({[Product].[All Products], [Product].[Drink]}, {[Store].[All Stores]}) ON ROWS
        FROM [Warehouse and Sales]
      MDX

      assert_equal [[131_558], [12_202]], result.values
    end

    # No calculated measure refers to the invalid measure, so only the
    # measures of the query contain it.
    it "evaluates an invalid measure on the columns axis" do
      @role_olap.role_name = "Female only"
      result = @role_olap.execute <<~MDX
        SELECT {[Measures].[Unit Sales], [Measures].[Not existing measure]} ON COLUMNS,
          NonEmptyCrossJoin({[Product].[All Products], [Product].[Drink]}, {[Store].[All Stores]}) ON ROWS
        FROM [Warehouse and Sales]
      MDX

      assert_equal [[131_558], [12_202]], result.values
    end

    # FoodMart has 1997 sales only for the stores in the USA.
    it "removes the empty rows for a measure that refers to an invalid measure" do
      assert_query_returns @role_olap, <<~MDX, <<~RESULT
        WITH MEMBER [Measures].[Invalid reference] AS
          [Measures].[Unit Sales] + [Measures].[Not existing measure]
        SELECT {[Measures].[Invalid reference]} ON COLUMNS,
          NonEmptyCrossJoin([Product].[Product Family].Members, [Store].[Store Country].Members) ON ROWS
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Invalid reference]}
        Axis #2:
        {[Product].[Drink], [Store].[USA]}
        {[Product].[Food], [Store].[USA]}
        {[Product].[Non-Consumable], [Store].[USA]}
        Row #0: 24,597
        Row #1: 191,940
        Row #2: 50,236
      RESULT
    end

    it "keeps the rows for a measure that refers only to an invalid measure" do
      skip "ClickHouse requires UNION ALL or UNION DISTINCT in virtual cube member SQL" if MONDRIAN_DRIVER == "clickhouse"

      result = @role_olap.execute <<~MDX
        WITH MEMBER [Measures].[Only invalid] AS [Measures].[Not existing measure]
        SELECT {[Measures].[Only invalid]} ON COLUMNS,
          NonEmptyCrossJoin({[Product].[Product Family].Members}, {[Store].[All Stores]}) ON ROWS
        FROM [Warehouse and Sales]
      MDX

      assert_equal [[nil], [nil], [nil]], result.values
    end
  end
end
