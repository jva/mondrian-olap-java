# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2003-2005 Julian Hyde
# Copyright (C) 2005-2021 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/FunctionTest.java
describe "Function set operations" do
  before(:all) do
    create_olap_connection
  end

  describe "Distinct" do
    # Java: FunctionTest#testDistinctTwoMembers
    it "removes duplicate from two identical members" do
      assert_axis_returns @olap,
        "Distinct({[Employees].[All Employees].[Sheri Nowmer].[Donna Arnold]," \
        "[Employees].[Sheri Nowmer].[Donna Arnold]})",
        "[Employees].[Sheri Nowmer].[Donna Arnold]",
        cube: "HR"
    end

    # Java: FunctionTest#testDistinctThreeMembers
    it "removes duplicate from three members with one repeat" do
      assert_axis_returns @olap,
        "Distinct({[Employees].[All Employees].[Sheri Nowmer].[Donna Arnold]," \
        "[Employees].[All Employees].[Sheri Nowmer].[Darren Stanz]," \
        "[Employees].[All Employees].[Sheri Nowmer].[Donna Arnold]})",
        <<~EXPECTED.chomp,
          [Employees].[Sheri Nowmer].[Donna Arnold]
          [Employees].[Sheri Nowmer].[Darren Stanz]
        EXPECTED
        cube: "HR"
    end

    # Java: FunctionTest#testDistinctFourMembers
    it "removes duplicates from four members with two repeats" do
      assert_axis_returns @olap,
        "Distinct({[Employees].[All Employees].[Sheri Nowmer].[Donna Arnold]," \
        "[Employees].[All Employees].[Sheri Nowmer].[Darren Stanz]," \
        "[Employees].[All Employees].[Sheri Nowmer].[Donna Arnold]," \
        "[Employees].[All Employees].[Sheri Nowmer].[Darren Stanz]})",
        <<~EXPECTED.chomp,
          [Employees].[Sheri Nowmer].[Donna Arnold]
          [Employees].[Sheri Nowmer].[Darren Stanz]
        EXPECTED
        cube: "HR"
    end

    # Java: FunctionTest#testDistinctTwoTuples
    it "removes duplicate tuple from two identical tuples" do
      assert_axis_returns @olap,
        "Distinct({([Time].[1997],[Store].[All Stores].[Mexico]), " \
        "([Time].[1997], [Store].[All Stores].[Mexico])})",
        "{[Time].[1997], [Store].[Mexico]}"
    end

    # Java: FunctionTest#testDistinctSomeTuples
    it "removes duplicate tuples from crossjoin result" do
      assert_axis_returns @olap,
        "Distinct({([Time].[1997],[Store].[All Stores].[Mexico]), " \
        "crossjoin({[Time].[1997]},{[Store].[All Stores].children})})",
        <<~EXPECTED.chomp
          {[Time].[1997], [Store].[Mexico]}
          {[Time].[1997], [Store].[Canada]}
          {[Time].[1997], [Store].[USA]}
        EXPECTED
    end
  end

  describe "Filter" do
    # Java: FunctionTest#testFilterWithSlicer
    # Make sure that slicer is in force when expression is applied on axis
    it "respects slicer when filtering axis members" do
      result = @olap.execute(<<~MDX)
        select {[Measures].[Unit Sales]} on columns,
         filter([Customers].[USA].children,
                [Measures].[Unit Sales] > 20000) on rows
        from Sales
        where ([Time].[1997].[Q1])
      MDX
      cell_set = result.raw_cell_set
      rows = cell_set.getAxes.get(1)
      # If slicer were ignored, there would be 3 rows
      assert_equal 1, rows.getPositions.size
      cell = cell_set.getCell(java.util.Arrays.asList(java.lang.Integer.new(0), java.lang.Integer.new(0)))
      assert_equal "30,114", cell.getFormattedValue
    end

    # Java: FunctionTest#testIsNullWithCalcMem
    it "IS NULL returns false for calculated member" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member Store.foo as '1010'
        member measures.bar as 'Store.currentmember IS NULL'
        SELECT measures.bar on 0, {Store.foo} on 1 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[bar]}
        Axis #2:
        {[Store].[foo]}
        Row #0: false
      RESULT
    end

    # Java: FunctionTest#testFilterCompound
    it "filters compound crossjoin set with slicer" do
      result = @olap.execute(<<~MDX)
        select {[Measures].[Unit Sales]} on columns,
          Filter(
            CrossJoin(
              [Gender].Children,
              [Customers].[USA].Children),
            [Measures].[Unit Sales] > 9500) on rows
        from Sales
        where ([Time].[1997].[Q1])
      MDX
      cell_set = result.raw_cell_set
      rows = cell_set.getAxes.get(1).getPositions
      assert_equal 3, rows.size
      assert_equal "F", rows.get(0).getMembers.get(0).getName
      assert_equal "WA", rows.get(0).getMembers.get(1).getName
      assert_equal "M", rows.get(1).getMembers.get(0).getName
      assert_equal "OR", rows.get(1).getMembers.get(1).getName
      assert_equal "M", rows.get(2).getMembers.get(0).getName
      assert_equal "WA", rows.get(2).getMembers.get(1).getName
    end

    # Java: FunctionTest#testFilterWillTimeout
    it "Filter times out on large crossjoin" do
      # This test uses SleepUdf which is a test-only Java class from BasicQueryTest,
      # not available in the production Mondrian JAR. Skipping.
      skip "SleepUdf not available in production JAR"
    end
  end

  describe "Generate" do
    # Java: FunctionTest#testGenerateDepends
    it "depends on the correct hierarchies" do
      # TODO: assertExprDependsOn not yet available
      skip "assertSetExprDependsOn not yet available"
    end

    # Java: FunctionTest#testGenerate
    it "generates children for each member in the input set" do
      assert_axis_returns @olap,
        "Generate({[Store].[USA], [Store].[USA].[CA]}, {[Store].CurrentMember.Children})",
        <<~EXPECTED.chomp
          [Store].[USA].[CA]
          [Store].[USA].[OR]
          [Store].[USA].[WA]
          [Store].[USA].[CA].[Alameda]
          [Store].[USA].[CA].[Beverly Hills]
          [Store].[USA].[CA].[Los Angeles]
          [Store].[USA].[CA].[San Diego]
          [Store].[USA].[CA].[San Francisco]
        EXPECTED
    end

    # Java: FunctionTest#testGenerateNonSet
    it "implicitly converts non-set arguments to sets" do
      # SSAS implicitly converts arg #2 to a set
      assert_axis_returns @olap,
        "Generate({[Store].[USA], [Store].[USA].[CA]}, [Store].PrevMember, ALL)",
        <<~EXPECTED.chomp
          [Store].[Mexico]
          [Store].[Mexico].[Zacatecas]
        EXPECTED

      # SSAS implicitly converts arg #1 to a set
      assert_axis_returns @olap,
        "Generate([Store].[USA], [Store].PrevMember, ALL)",
        "[Store].[Mexico]"
    end

    # Java: FunctionTest#testGenerateAll
    it "ALL flag preserves duplicates in generated set" do
      assert_axis_returns @olap,
        "Generate({[Store].[USA].[CA], [Store].[USA].[OR].[Portland]}," \
        " Ascendants([Store].CurrentMember)," \
        " ALL)",
        <<~EXPECTED.chomp
          [Store].[USA].[CA]
          [Store].[USA]
          [Store].[All Stores]
          [Store].[USA].[OR].[Portland]
          [Store].[USA].[OR]
          [Store].[USA]
          [Store].[All Stores]
        EXPECTED
    end

    # Java: FunctionTest#testGenerateUnique
    it "default behavior removes duplicates from generated set" do
      assert_axis_returns @olap,
        "Generate({[Store].[USA].[CA], [Store].[USA].[OR].[Portland]}," \
        " Ascendants([Store].CurrentMember))",
        <<~EXPECTED.chomp
          [Store].[USA].[CA]
          [Store].[USA]
          [Store].[All Stores]
          [Store].[USA].[OR].[Portland]
          [Store].[USA].[OR]
        EXPECTED
    end

    # Java: FunctionTest#testGenerateUniqueTuple
    it "removes duplicate tuples from generated set" do
      assert_axis_returns @olap,
        "Generate({([Store].[USA].[CA],[Product].[All Products]), " \
        "([Store].[USA].[CA],[Product].[All Products])}," \
        "{([Store].CurrentMember, [Product].CurrentMember)})",
        "{[Store].[USA].[CA], [Product].[All Products]}"
    end

    # Java: FunctionTest#testGenerateCrossJoin
    it "generates crossjoin with different top 2 per region" do
      # Note that the different regions have different Top 2.
      assert_axis_returns @olap,
        "Generate({[Store].[USA].[CA], [Store].[USA].[CA].[San Francisco]},\n" \
        "  CrossJoin({[Store].CurrentMember},\n" \
        "    TopCount([Product].[Brand Name].members, \n" \
        "    2,\n" \
        "    [Measures].[Unit Sales])))",
        <<~EXPECTED.chomp
          {[Store].[USA].[CA], [Product].[Food].[Produce].[Vegetables].[Fresh Vegetables].[Hermanos]}
          {[Store].[USA].[CA], [Product].[Food].[Produce].[Vegetables].[Fresh Vegetables].[Tell Tale]}
          {[Store].[USA].[CA].[San Francisco], [Product].[Food].[Produce].[Vegetables].[Fresh Vegetables].[Ebony]}
          {[Store].[USA].[CA].[San Francisco], [Product].[Food].[Produce].[Vegetables].[Fresh Vegetables].[High Top]}
        EXPECTED
    end

    # Java: FunctionTest#testGenerateString
    it "generates concatenated string from set members" do
      assert_expression_returns @olap,
        "Generate({Time.[1997], Time.[1998]}," \
        " Time.[Time].CurrentMember.Name)",
        "19971998"

      assert_expression_returns @olap,
        "Generate({Time.[1997], Time.[1998]}," \
        ' Time.[Time].CurrentMember.Name, " and ")',
        "1997 and 1998"
    end

    # Java: FunctionTest#testGenerateWillTimeout
    it "Generate times out on very large nested generation" do
      with_properties(QueryTimeout: 5, EnableNativeNonEmpty: false) do
        error = assert_raises(Mondrian::OLAP::Error) do
          @olap.execute(
            "SELECT {Generate([Product].[Product Name].members," \
            "  Generate([Customers].[Name].members, " \
            "    {([Store].CurrentMember, [Product].CurrentMember, [Customers].CurrentMember)}))} ON 0" \
            " FROM [Sales]"
          )
        end
        assert_match(/timeout|cancel/i, error.message)
      end
    end

    # Java: FunctionTest#testGenerateForStringMemberProperty
    # Test case for the issue: MONDRIAN-2402
    it "generates string from member MEMBER_CAPTION property" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Store].[Lineage of Time] AS
         Generate(Ascendants([Time].CurrentMember), [Time].CurrentMember.Properties("MEMBER_CAPTION"), ",")
         SELECT
          {[Time].[1997]} ON Axis(0),
          Union(
           {([Store].[Lineage of Time])},
           {[Store].[All Stores]}) ON Axis(1)
         FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997]}
        Axis #2:
        {[Store].[Lineage of Time]}
        {[Store].[All Stores]}
        Row #0: 1997
        Row #1: 266,773
      RESULT
    end
  end

  describe "Head" do
    # Java: FunctionTest#testHead
    it "returns first N members" do
      assert_axis_returns @olap,
        "Head([Store].Children, 2)",
        <<~EXPECTED.chomp
          [Store].[Canada]
          [Store].[Mexico]
        EXPECTED
    end

    # Java: FunctionTest#testHeadNegative
    it "returns empty set for negative count" do
      assert_axis_returns @olap,
        "Head([Store].Children, 2 - 3)",
        ""
    end

    # Java: FunctionTest#testHeadDefault
    it "returns first member when count is omitted" do
      assert_axis_returns @olap,
        "Head([Store].Children)",
        "[Store].[Canada]"
    end

    # Java: FunctionTest#testHeadOvershoot
    it "returns all members when count exceeds set size" do
      assert_axis_returns @olap,
        "Head([Store].Children, 2 + 2)",
        <<~EXPECTED.chomp
          [Store].[Canada]
          [Store].[Mexico]
          [Store].[USA]
        EXPECTED
    end

    # Java: FunctionTest#testHeadEmpty
    it "returns empty set from empty input" do
      assert_axis_returns @olap,
        "Head([Gender].[F].Children, 2)",
        ""

      assert_axis_returns @olap,
        "Head([Gender].[F].Children)",
        ""
    end

    # Java: FunctionTest#testHeadBug
    # Test case for bug 2488492, "Union between calc mem and head function throws exception"
    it "Union with Head and calculated member does not throw exception" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        SELECT
                        UNION(
                            {([Customers].CURRENTMEMBER)},
                            HEAD(
                                {([Customers].CURRENTMEMBER)},
                                IIF(
                                    COUNT(
                                        FILTER(
                                            DESCENDANTS(
                                                [Customers].CURRENTMEMBER,
                                                [Customers].[Country]),
                                            [Measures].[Unit Sales] >= 66),
                                        INCLUDEEMPTY)> 0,
                                    1,
                                    0)),
                            ALL)
            ON AXIS(0)
        FROM
            [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[All Customers]}
        {[Customers].[All Customers]}
        Row #0: 266,773
        Row #0: 266,773
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH
            MEMBER
                [Customers].[COG_OQP_INT_t2]AS '1',
                SOLVE_ORDER = 65535
        SELECT
                        UNION(
                            {([Customers].[COG_OQP_INT_t2])},
                            HEAD(
                                {([Customers].CURRENTMEMBER)},
                                IIF(
                                    COUNT(
                                        FILTER(
                                            DESCENDANTS(
                                                [Customers].CURRENTMEMBER,
                                                [Customers].[Country]),
                                            [Measures].[Unit Sales]>= 66),
                                        INCLUDEEMPTY)> 0,
                                    1,
                                    0)),
                            ALL)
            ON AXIS(0)
        FROM
            [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[COG_OQP_INT_t2]}
        {[Customers].[All Customers]}
        Row #0: 1
        Row #0: 266,773
      RESULT

      # More minimal test case. Also demonstrates similar problem with Tail.
      assert_axis_returns @olap,
        "Union(\n" \
        "  Union(\n" \
        "    Tail([Customers].[USA].[CA].Children, 2),\n" \
        "    Head([Customers].[USA].[WA].Children, 2),\n" \
        "    ALL),\n" \
        "  Tail([Customers].[USA].[OR].Children, 2)," \
        "  ALL)",
        <<~EXPECTED.chomp
          [Customers].[USA].[CA].[West Covina]
          [Customers].[USA].[CA].[Woodland Hills]
          [Customers].[USA].[WA].[Anacortes]
          [Customers].[USA].[WA].[Ballard]
          [Customers].[USA].[OR].[W. Linn]
          [Customers].[USA].[OR].[Woodburn]
        EXPECTED
    end
  end

  describe "Hierarchize" do
    # Java: FunctionTest#testHierarchize
    it "orders members in hierarchy order (PRE by default)" do
      assert_axis_returns @olap,
        "Hierarchize(\n" \
        "    {[Product].[All Products], " \
        "     [Product].[Food],\n" \
        "     [Product].[Drink],\n" \
        "     [Product].[Non-Consumable],\n" \
        "     [Product].[Food].[Eggs],\n" \
        "     [Product].[Drink].[Dairy]})",
        <<~EXPECTED.chomp
          [Product].[All Products]
          [Product].[Drink]
          [Product].[Drink].[Dairy]
          [Product].[Food]
          [Product].[Food].[Eggs]
          [Product].[Non-Consumable]
        EXPECTED
    end

    # Java: FunctionTest#testHierarchizePost
    it "orders members in POST hierarchy order" do
      assert_axis_returns @olap,
        "Hierarchize(\n" \
        "    {[Product].[All Products], " \
        "     [Product].[Food],\n" \
        "     [Product].[Food].[Eggs],\n" \
        "     [Product].[Drink].[Dairy]},\n" \
        "  POST)",
        <<~EXPECTED.chomp
          [Product].[Drink].[Dairy]
          [Product].[Food].[Eggs]
          [Product].[Food]
          [Product].[All Products]
        EXPECTED
    end

    # Java: FunctionTest#testHierarchizePC
    it "hierarchizes parent-child hierarchy members" do
      assert_axis_returns @olap,
        "Hierarchize(\n" \
        "   { Subset([Employees].Members, 90, 10),\n" \
        "     Head([Employees].Members, 5) })",
        <<~EXPECTED.chomp,
          [Employees].[All Employees]
          [Employees].[Sheri Nowmer]
          [Employees].[Sheri Nowmer].[Derrick Whelply]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Beverly Baker]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Beverly Baker].[Shauna Wyro]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Leopoldo Renfro]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Donna Brockett]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Laurie Anderson]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Louis Gomez]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Melvin Glass]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Kristin Cohen]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Susan Kharman]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Gordon Kirschner]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Geneva Kouba]
          [Employees].[Sheri Nowmer].[Derrick Whelply].[Pedro Castillo].[Lin Conley].[Paul Tays].[Cheryl Thorton].[Tricia Clark]
        EXPECTED
        cube: "HR"
    end

    # Java: FunctionTest#testHierarchizeCrossJoinPre
    it "hierarchizes crossjoin set in PRE order" do
      assert_axis_returns @olap,
        "Hierarchize(\n" \
        "  CrossJoin(\n" \
        "    {[Product].[All Products], " \
        "     [Product].[Food],\n" \
        "     [Product].[Food].[Eggs],\n" \
        "     [Product].[Drink].[Dairy]},\n" \
        "    [Gender].MEMBERS),\n" \
        "  PRE)",
        <<~EXPECTED.chomp
          {[Product].[All Products], [Gender].[All Gender]}
          {[Product].[All Products], [Gender].[F]}
          {[Product].[All Products], [Gender].[M]}
          {[Product].[Drink].[Dairy], [Gender].[All Gender]}
          {[Product].[Drink].[Dairy], [Gender].[F]}
          {[Product].[Drink].[Dairy], [Gender].[M]}
          {[Product].[Food], [Gender].[All Gender]}
          {[Product].[Food], [Gender].[F]}
          {[Product].[Food], [Gender].[M]}
          {[Product].[Food].[Eggs], [Gender].[All Gender]}
          {[Product].[Food].[Eggs], [Gender].[F]}
          {[Product].[Food].[Eggs], [Gender].[M]}
        EXPECTED
    end

    # Java: FunctionTest#testHierarchizeCrossJoinPost
    it "hierarchizes crossjoin set in POST order" do
      assert_axis_returns @olap,
        "Hierarchize(\n" \
        "  CrossJoin(\n" \
        "    {[Product].[All Products], " \
        "     [Product].[Food],\n" \
        "     [Product].[Food].[Eggs],\n" \
        "     [Product].[Drink].[Dairy]},\n" \
        "    [Gender].MEMBERS),\n" \
        "  POST)",
        <<~EXPECTED.chomp
          {[Product].[Drink].[Dairy], [Gender].[F]}
          {[Product].[Drink].[Dairy], [Gender].[M]}
          {[Product].[Drink].[Dairy], [Gender].[All Gender]}
          {[Product].[Food].[Eggs], [Gender].[F]}
          {[Product].[Food].[Eggs], [Gender].[M]}
          {[Product].[Food].[Eggs], [Gender].[All Gender]}
          {[Product].[Food], [Gender].[F]}
          {[Product].[Food], [Gender].[M]}
          {[Product].[Food], [Gender].[All Gender]}
          {[Product].[All Products], [Gender].[F]}
          {[Product].[All Products], [Gender].[M]}
          {[Product].[All Products], [Gender].[All Gender]}
        EXPECTED
    end

    # Java: FunctionTest#testHierarchizeOrdinal
    # Tests that the Hierarchize function works correctly when applied to a level
    # whose ordering is determined by an 'ordinal' property.
    it "hierarchizes levels ordered by ordinal column" do
      cube_xml = <<~XML
        <Cube name="Sales_Hierarchize">
          <Table name="sales_fact_1997"/>
          <Dimension name="Time_Alphabetical" type="TimeDimension" foreignKey="time_id">
            <Hierarchy hasAll="false" primaryKey="time_id">
              <Table name="time_by_day"/>
              <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true"
                  levelType="TimeYears"/>
              <Level name="Quarter" column="quarter" uniqueMembers="false"
                  levelType="TimeQuarters"/>
              <Level name="Month" column="month_of_year" uniqueMembers="false" type="Numeric"
                  ordinalColumn="the_month"
                  levelType="TimeMonths"/>
            </Hierarchy>
          </Dimension>

          <Dimension name="Month_Alphabetical" type="TimeDimension" foreignKey="time_id">
            <Hierarchy hasAll="false" primaryKey="time_id">
              <Table name="time_by_day"/>
              <Level name="Month" column="month_of_year" uniqueMembers="false" type="Numeric"
                  ordinalColumn="the_month"
                  levelType="TimeMonths"/>
            </Hierarchy>
          </Dimension>

          <Measure name="Unit Sales" column="unit_sales" aggregator="sum"
              formatString="Standard"/>
        </Cube>
      XML
      schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
      params = CONNECTION_PARAMS.merge(catalog_content: schema)
      params.delete(:catalog)
      olap = Mondrian::OLAP::Connection.create(params)
      begin
        # The [Time_Alphabetical] is ordered alphabetically by month
        assert_axis_returns olap,
          "Hierarchize([Time_Alphabetical].members)",
          <<~EXPECTED.chomp,
            [Time_Alphabetical].[1997]
            [Time_Alphabetical].[1997].[Q1]
            [Time_Alphabetical].[1997].[Q1].[2]
            [Time_Alphabetical].[1997].[Q1].[1]
            [Time_Alphabetical].[1997].[Q1].[3]
            [Time_Alphabetical].[1997].[Q2]
            [Time_Alphabetical].[1997].[Q2].[4]
            [Time_Alphabetical].[1997].[Q2].[6]
            [Time_Alphabetical].[1997].[Q2].[5]
            [Time_Alphabetical].[1997].[Q3]
            [Time_Alphabetical].[1997].[Q3].[8]
            [Time_Alphabetical].[1997].[Q3].[7]
            [Time_Alphabetical].[1997].[Q3].[9]
            [Time_Alphabetical].[1997].[Q4]
            [Time_Alphabetical].[1997].[Q4].[12]
            [Time_Alphabetical].[1997].[Q4].[11]
            [Time_Alphabetical].[1997].[Q4].[10]
            [Time_Alphabetical].[1998]
            [Time_Alphabetical].[1998].[Q1]
            [Time_Alphabetical].[1998].[Q1].[2]
            [Time_Alphabetical].[1998].[Q1].[1]
            [Time_Alphabetical].[1998].[Q1].[3]
            [Time_Alphabetical].[1998].[Q2]
            [Time_Alphabetical].[1998].[Q2].[4]
            [Time_Alphabetical].[1998].[Q2].[6]
            [Time_Alphabetical].[1998].[Q2].[5]
            [Time_Alphabetical].[1998].[Q3]
            [Time_Alphabetical].[1998].[Q3].[8]
            [Time_Alphabetical].[1998].[Q3].[7]
            [Time_Alphabetical].[1998].[Q3].[9]
            [Time_Alphabetical].[1998].[Q4]
            [Time_Alphabetical].[1998].[Q4].[12]
            [Time_Alphabetical].[1998].[Q4].[11]
            [Time_Alphabetical].[1998].[Q4].[10]
          EXPECTED
          cube: "Sales_Hierarchize"

        # The [Month_Alphabetical] is a single-level hierarchy ordered
        # alphabetically by month.
        assert_axis_returns olap,
          "Hierarchize([Month_Alphabetical].members)",
          <<~EXPECTED.chomp,
            [Month_Alphabetical].[4]
            [Month_Alphabetical].[8]
            [Month_Alphabetical].[12]
            [Month_Alphabetical].[2]
            [Month_Alphabetical].[1]
            [Month_Alphabetical].[7]
            [Month_Alphabetical].[6]
            [Month_Alphabetical].[3]
            [Month_Alphabetical].[5]
            [Month_Alphabetical].[11]
            [Month_Alphabetical].[10]
            [Month_Alphabetical].[9]
          EXPECTED
          cube: "Sales_Hierarchize"
      ensure
        olap.close
        Mondrian::OLAP::Connection.flush_schema_cache
      end
    end
  end

  describe "Intersect" do
    # Java: FunctionTest#testIntersectAll
    it "ALL flag preserves duplicates from left set" do
      # Note: duplicates retained from left, not from right; and order is preserved.
      assert_axis_returns @olap,
        "Intersect({[Time].[1997].[Q2], [Time].[1997], [Time].[1997].[Q1], [Time].[1997].[Q2]}, " \
        "{[Time].[1998], [Time].[1997], [Time].[1997].[Q2], [Time].[1997]}, " \
        "ALL)",
        <<~EXPECTED.chomp
          [Time].[1997].[Q2]
          [Time].[1997]
          [Time].[1997].[Q2]
        EXPECTED
    end

    # Java: FunctionTest#testIntersect
    it "removes duplicates by default and preserves first occurrence order" do
      # Duplicates not preserved. Output in order that first duplicate occurred.
      assert_axis_returns @olap,
        "Intersect(\n" \
        "  {[Time].[1997].[Q2], [Time].[1997], [Time].[1997].[Q1], [Time].[1997].[Q2]}, " \
        "{[Time].[1998], [Time].[1997], [Time].[1997].[Q2], [Time].[1997]})",
        <<~EXPECTED.chomp
          [Time].[1997].[Q2]
          [Time].[1997]
        EXPECTED
    end

    # Java: FunctionTest#testIntersectTuples
    it "intersects tuple sets" do
      assert_axis_returns @olap,
        "Intersect(\n" \
        "  {([Time].[1997].[Q2], [Gender].[M]),\n" \
        "   ([Time].[1997], [Gender].[F]),\n" \
        "   ([Time].[1997].[Q1], [Gender].[M]),\n" \
        "   ([Time].[1997].[Q2], [Gender].[M])},\n" \
        "  {([Time].[1998], [Gender].[F]),\n" \
        "   ([Time].[1997], [Gender].[F]),\n" \
        "   ([Time].[1997].[Q2], [Gender].[M]),\n" \
        "   ([Time].[1997], [Gender])})",
        <<~EXPECTED.chomp
          {[Time].[1997].[Q2], [Gender].[M]}
          {[Time].[1997], [Gender].[F]}
        EXPECTED
    end

    # Java: FunctionTest#testIntersectRightEmpty
    it "returns empty set when right set is empty" do
      assert_axis_returns @olap,
        "Intersect({[Time].[1997]}, {})",
        ""
    end

    # Java: FunctionTest#testIntersectLeftEmpty
    it "returns empty set when left set is empty" do
      assert_axis_returns @olap,
        "Intersect({}, {[Store].[USA].[CA]})",
        ""
    end
  end

  describe "Subset" do
    # Java: FunctionTest#testSubset
    it "returns specified slice of set" do
      assert_axis_returns @olap,
        "Subset([Promotion Media].Children, 7, 2)",
        <<~EXPECTED.chomp
          [Promotion Media].[Product Attachment]
          [Promotion Media].[Radio]
        EXPECTED
    end

    # Java: FunctionTest#testSubsetNegativeCount
    it "returns empty set for negative count" do
      assert_axis_returns @olap,
        "Subset([Promotion Media].Children, 3, -1)",
        ""
    end

    # Java: FunctionTest#testSubsetNegativeStart
    it "returns empty set for negative start" do
      assert_axis_returns @olap,
        "Subset([Promotion Media].Children, -2, 4)",
        ""
    end

    # Java: FunctionTest#testSubsetDefault
    it "returns all from start when count is omitted" do
      assert_axis_returns @olap,
        "Subset([Promotion Media].Children, 11)",
        <<~EXPECTED.chomp
          [Promotion Media].[Sunday Paper, Radio]
          [Promotion Media].[Sunday Paper, Radio, TV]
          [Promotion Media].[TV]
        EXPECTED
    end

    # Java: FunctionTest#testSubsetOvershoot
    it "returns empty set when start exceeds set size" do
      assert_axis_returns @olap,
        "Subset([Promotion Media].Children, 15)",
        ""
    end

    # Java: FunctionTest#testSubsetEmpty
    it "returns empty set from empty input" do
      assert_axis_returns @olap,
        "Subset([Gender].[F].Children, 1)",
        ""

      assert_axis_returns @olap,
        "Subset([Gender].[F].Children, 1, 3)",
        ""
    end
  end

  describe "Tail" do
    # Java: FunctionTest#testTail
    it "returns last N members" do
      assert_axis_returns @olap,
        "Tail([Store].Children, 2)",
        <<~EXPECTED.chomp
          [Store].[Mexico]
          [Store].[USA]
        EXPECTED
    end

    # Java: FunctionTest#testTailNegative
    it "returns empty set for negative count" do
      assert_axis_returns @olap,
        "Tail([Store].Children, 2 - 3)",
        ""
    end

    # Java: FunctionTest#testTailDefault
    it "returns last member when count is omitted" do
      assert_axis_returns @olap,
        "Tail([Store].Children)",
        "[Store].[USA]"
    end

    # Java: FunctionTest#testTailOvershoot
    it "returns all members when count exceeds set size" do
      assert_axis_returns @olap,
        "Tail([Store].Children, 2 + 2)",
        <<~EXPECTED.chomp
          [Store].[Canada]
          [Store].[Mexico]
          [Store].[USA]
        EXPECTED
    end

    # Java: FunctionTest#testTailEmpty
    it "returns empty set from empty input" do
      assert_axis_returns @olap,
        "Tail([Gender].[F].Children, 2)",
        ""

      assert_axis_returns @olap,
        "Tail([Gender].[F].Children)",
        ""
    end
  end
end
