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
describe "Function ordering (Order, Unorder, ToggleDrillState)" do
  before(:all) do
    create_olap_connection
  end

  def root_cause_message(exception)
    cause = exception
    cause = cause.cause while cause.cause && cause.cause != cause
    cause.message
  end

  describe "Order" do
    # Java: FunctionTest#testOrderDepends
    it "depends on value expression dimensions except set dimensions" do
      skip "TODO: assertSetExprDependsOn not yet available"
    end

    # Java: FunctionTest#testOrderCalc
    it "compiles Order with various calc plans" do
      skip "TODO: assertAxisCompilesTo not yet available"
    end

    # Java: FunctionTest#testOrderWithMember
    # Verifies that the order function works with a defined member.
    # See: http://forums.pentaho.com/showthread.php?p=179473#post179473
    it "sorts by a calculated member" do
      assert_query_returns @olap,
        "with member [Measures].[Product Name Length] as " \
        "'LEN([Product].CurrentMember.Name)'\n" \
        "select {[Measures].[Product Name Length]} ON COLUMNS,\n" \
        "Order([Product].[All Products].Children, " \
        "[Measures].[Product Name Length], BASC) ON ROWS\n" \
        "from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Product Name Length]}
          Axis #2:
          {[Product].[Food]}
          {[Product].[Drink]}
          {[Product].[Non-Consumable]}
          Row #0: 4
          Row #1: 5
          Row #2: 14
        RESULT
    end

    # Java: FunctionTest#testOrderNonEmpty
    # Test case for bug #1797159, Potential MDX Order Non Empty Problem
    it "works with NON EMPTY" do
      assert_query_returns @olap,
        "select NON EMPTY [Gender].Members ON COLUMNS,\n" \
        "NON EMPTY Order([Product].[All Products].[Drink].Children,\n" \
        "[Gender].[All Gender].[F], ASC) ON ROWS\n" \
        "from [Sales]\n" \
        "where ([Customers].[All Customers].[USA].[CA].[San Francisco],\n" \
        " [Time].[1997])",
        <<~RESULT
          Axis #0:
          {[Customers].[USA].[CA].[San Francisco], [Time].[1997]}
          Axis #1:
          {[Gender].[All Gender]}
          {[Gender].[F]}
          {[Gender].[M]}
          Axis #2:
          {[Product].[Drink].[Beverages]}
          {[Product].[Drink].[Alcoholic Beverages]}
          Row #0: 2
          Row #0:
          Row #0: 2
          Row #1: 4
          Row #1: 2
          Row #1: 2
        RESULT
    end

    # Java: FunctionTest#testOrder
    it "sorts members by unit sales preserving hierarchy" do
      assert_query_returns @olap,
        "select {[Measures].[Unit Sales]} on columns,\n" \
        " order({\n" \
        "  [Product].[All Products].[Drink],\n" \
        "  [Product].[All Products].[Drink].[Beverages],\n" \
        "  [Product].[All Products].[Drink].[Dairy],\n" \
        "  [Product].[All Products].[Food],\n" \
        "  [Product].[All Products].[Food].[Baked Goods],\n" \
        "  [Product].[All Products].[Food].[Eggs],\n" \
        "  [Product].[All Products]},\n" \
        " [Measures].[Unit Sales]) on rows\n" \
        "from Sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Unit Sales]}
          Axis #2:
          {[Product].[All Products]}
          {[Product].[Drink]}
          {[Product].[Drink].[Dairy]}
          {[Product].[Drink].[Beverages]}
          {[Product].[Food]}
          {[Product].[Food].[Eggs]}
          {[Product].[Food].[Baked Goods]}
          Row #0: 266,773
          Row #1: 24,597
          Row #2: 4,186
          Row #3: 13,573
          Row #4: 191,940
          Row #5: 4,132
          Row #6: 7,870
        RESULT
    end

    # Java: FunctionTest#testOrderParentsMissing
    it "sorts members with missing parents in hierarchy" do
      # Paradoxically, [Alcoholic Beverages] comes before
      # [Eggs] even though it has a larger value, because
      # its parent [Drink] has a smaller value than [Food].
      assert_query_returns @olap,
        "select {[Measures].[Unit Sales]} on columns," \
        " order({\n" \
        "  [Product].[All Products].[Drink].[Alcoholic Beverages],\n" \
        "  [Product].[All Products].[Food].[Eggs]},\n" \
        " [Measures].[Unit Sales], ASC) on rows\n" \
        "from Sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Unit Sales]}
          Axis #2:
          {[Product].[Drink].[Alcoholic Beverages]}
          {[Product].[Food].[Eggs]}
          Row #0: 6,838
          Row #1: 4,132
        RESULT
    end

    # Java: FunctionTest#testOrderCrossJoinBreak
    it "sorts cross join with BDESC" do
      assert_query_returns @olap,
        "select {[Measures].[Unit Sales]} on columns,\n" \
        "  Order(\n" \
        "    CrossJoin(\n" \
        "      [Gender].children,\n" \
        "      [Marital Status].children),\n" \
        "    [Measures].[Unit Sales],\n" \
        "    BDESC) on rows\n" \
        "from Sales\n" \
        "where [Time].[1997].[Q1]",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q1]}
          Axis #1:
          {[Measures].[Unit Sales]}
          Axis #2:
          {[Gender].[M], [Marital Status].[S]}
          {[Gender].[F], [Marital Status].[M]}
          {[Gender].[M], [Marital Status].[M]}
          {[Gender].[F], [Marital Status].[S]}
          Row #0: 17,070
          Row #1: 16,790
          Row #2: 16,311
          Row #3: 16,120
        RESULT
    end

    # Java: FunctionTest#testOrderCrossJoin
    it "sorts cross join preserving hierarchy" do
      # Note:
      # 1. [Alcoholic Beverages] collates before [Eggs] and
      #    [Seafood] because its parent, [Drink], is less
      #    than [Food]
      # 2. [Seattle] generally sorts after [CA] and [OR]
      #    because invisible parent [WA] is greater.
      assert_query_returns @olap,
        "select CrossJoin(\n" \
        "    {[Time].[1997],\n" \
        "     [Time].[1997].[Q1]},\n" \
        "    {[Measures].[Unit Sales]}) on columns,\n" \
        "  Order(\n" \
        "    CrossJoin(\n" \
        "      {[Product].[All Products].[Food].[Eggs],\n" \
        "       [Product].[All Products].[Food].[Seafood],\n" \
        "       [Product].[All Products].[Drink].[Alcoholic Beverages]},\n" \
        "      {[Store].[USA].[WA].[Seattle],\n" \
        "       [Store].[USA].[CA],\n" \
        "       [Store].[USA].[OR]}),\n" \
        "    ([Time].[1997].[Q1], [Measures].[Unit Sales]),\n" \
        "    ASC) on rows\n" \
        "from Sales",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Time].[1997], [Measures].[Unit Sales]}
          {[Time].[1997].[Q1], [Measures].[Unit Sales]}
          Axis #2:
          {[Product].[Drink].[Alcoholic Beverages], [Store].[USA].[OR]}
          {[Product].[Drink].[Alcoholic Beverages], [Store].[USA].[CA]}
          {[Product].[Drink].[Alcoholic Beverages], [Store].[USA].[WA].[Seattle]}
          {[Product].[Food].[Seafood], [Store].[USA].[CA]}
          {[Product].[Food].[Seafood], [Store].[USA].[OR]}
          {[Product].[Food].[Seafood], [Store].[USA].[WA].[Seattle]}
          {[Product].[Food].[Eggs], [Store].[USA].[CA]}
          {[Product].[Food].[Eggs], [Store].[USA].[OR]}
          {[Product].[Food].[Eggs], [Store].[USA].[WA].[Seattle]}
          Row #0: 1,680
          Row #0: 393
          Row #1: 1,936
          Row #1: 431
          Row #2: 635
          Row #2: 142
          Row #3: 441
          Row #3: 91
          Row #4: 451
          Row #4: 107
          Row #5: 217
          Row #5: 44
          Row #6: 1,116
          Row #6: 240
          Row #7: 1,119
          Row #7: 251
          Row #8: 373
          Row #8: 57
        RESULT
    end

    # Java: FunctionTest#testOrderHierarchicalDesc
    it "sorts hierarchically DESC" do
      assert_axis_returns @olap,
        "Order(\n" \
        "    {[Product].[All Products], " \
        "     [Product].[Food],\n" \
        "     [Product].[Drink],\n" \
        "     [Product].[Non-Consumable],\n" \
        "     [Product].[Food].[Eggs],\n" \
        "     [Product].[Drink].[Dairy]},\n" \
        "  [Measures].[Unit Sales],\n" \
        "  DESC)",
        <<~EXPECTED.chomp
          [Product].[All Products]
          [Product].[Food]
          [Product].[Food].[Eggs]
          [Product].[Non-Consumable]
          [Product].[Drink]
          [Product].[Drink].[Dairy]
        EXPECTED
    end

    # Java: FunctionTest#testOrderCrossJoinDesc
    it "sorts cross join DESC preserving hierarchy" do
      assert_axis_returns @olap,
        "Order(\n" \
        "  CrossJoin(\n" \
        "    {[Gender].[M], [Gender].[F]},\n" \
        "    {[Product].[All Products], " \
        "     [Product].[Food],\n" \
        "     [Product].[Drink],\n" \
        "     [Product].[Non-Consumable],\n" \
        "     [Product].[Food].[Eggs],\n" \
        "     [Product].[Drink].[Dairy]}),\n" \
        "  [Measures].[Unit Sales],\n" \
        "  DESC)",
        <<~EXPECTED.chomp
          {[Gender].[M], [Product].[All Products]}
          {[Gender].[M], [Product].[Food]}
          {[Gender].[M], [Product].[Food].[Eggs]}
          {[Gender].[M], [Product].[Non-Consumable]}
          {[Gender].[M], [Product].[Drink]}
          {[Gender].[M], [Product].[Drink].[Dairy]}
          {[Gender].[F], [Product].[All Products]}
          {[Gender].[F], [Product].[Food]}
          {[Gender].[F], [Product].[Food].[Eggs]}
          {[Gender].[F], [Product].[Non-Consumable]}
          {[Gender].[F], [Product].[Drink]}
          {[Gender].[F], [Product].[Drink].[Dairy]}
        EXPECTED
    end

    # Java: FunctionTest#testOrderBug656802
    it "sorts with ToggleDrillState and Order DESC (bug 656802)" do
      # Note:
      # 1. [Alcoholic Beverages] collates before [Eggs] and
      #    [Seafood] because its parent, [Drink], is less
      #    than [Food]
      # 2. [Seattle] generally sorts after [CA] and [OR]
      #    because invisible parent [WA] is greater.
      assert_query_returns @olap,
        "select {[Measures].[Unit Sales], [Measures].[Store Cost], [Measures].[Store Sales]} ON columns, \n" \
        "Order(\n" \
        "  ToggleDrillState(\n" \
        "    {([Promotion Media].[All Media], [Product].[All Products])},\n" \
        "    {[Product].[All Products]}), \n" \
        "  [Measures].[Unit Sales], DESC) ON rows \n" \
        "from [Sales] where ([Time].[1997])",
        <<~RESULT
          Axis #0:
          {[Time].[1997]}
          Axis #1:
          {[Measures].[Unit Sales]}
          {[Measures].[Store Cost]}
          {[Measures].[Store Sales]}
          Axis #2:
          {[Promotion Media].[All Media], [Product].[All Products]}
          {[Promotion Media].[All Media], [Product].[Food]}
          {[Promotion Media].[All Media], [Product].[Non-Consumable]}
          {[Promotion Media].[All Media], [Product].[Drink]}
          Row #0: 266,773
          Row #0: 225,627.23
          Row #0: 565,238.13
          Row #1: 191,940
          Row #1: 163,270.72
          Row #1: 409,035.59
          Row #2: 50,236
          Row #2: 42,879.28
          Row #2: 107,366.33
          Row #3: 24,597
          Row #3: 19,477.23
          Row #3: 48,836.21
        RESULT
    end

    # Java: FunctionTest#testOrderBug712702_Simplified
    it "sorts year members by unit sales (bug 712702 simplified)" do
      assert_query_returns @olap,
        "SELECT Order({[Time].[Year].members}, [Measures].[Unit Sales]) on columns\n" \
        "from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Time].[1998]}
          {[Time].[1997]}
          Row #0:
          Row #0: 266,773
        RESULT
    end

    # Java: FunctionTest#testOrderBug712702_Original
    it "sorts cross join with average unit sales (bug 712702 original)" do
      assert_query_returns @olap,
        "with member [Measures].[Average Unit Sales] as 'Avg(Descendants([Time].[Time].CurrentMember, [Time].[Month]), \n" \
        "[Measures].[Unit Sales])' \n" \
        "member [Measures].[Max Unit Sales] as 'Max(Descendants([Time].[Time].CurrentMember, [Time].[Month]), " \
        "[Measures].[Unit Sales])' \n" \
        "select {[Measures].[Average Unit Sales], [Measures].[Max Unit Sales], [Measures].[Unit Sales]} ON columns," \
        " \n" \
        "  NON EMPTY Order(\n" \
        "    Crossjoin(\n" \
        "      {[Store].[USA].[OR].[Portland],\n" \
        "       [Store].[USA].[OR].[Salem],\n" \
        "       [Store].[USA].[OR].[Salem].[Store 13],\n" \
        "       [Store].[USA].[CA].[San Francisco],\n" \
        "       [Store].[USA].[CA].[San Diego],\n" \
        "       [Store].[USA].[CA].[Beverly Hills],\n" \
        "       [Store].[USA].[CA].[Los Angeles],\n" \
        "       [Store].[USA].[WA].[Walla Walla],\n" \
        "       [Store].[USA].[WA].[Bellingham],\n" \
        "       [Store].[USA].[WA].[Yakima],\n" \
        "       [Store].[USA].[WA].[Spokane],\n" \
        "       [Store].[USA].[WA].[Seattle], \n" \
        "       [Store].[USA].[WA].[Bremerton],\n" \
        "       [Store].[USA].[WA].[Tacoma]},\n" \
        "     [Time].[Year].Members), \n" \
        "  [Measures].[Average Unit Sales], ASC) ON rows\n" \
        "from [Sales] ",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Average Unit Sales]}
          {[Measures].[Max Unit Sales]}
          {[Measures].[Unit Sales]}
          Axis #2:
          {[Store].[USA].[OR].[Portland], [Time].[1997]}
          {[Store].[USA].[OR].[Salem], [Time].[1997]}
          {[Store].[USA].[OR].[Salem].[Store 13], [Time].[1997]}
          {[Store].[USA].[CA].[San Francisco], [Time].[1997]}
          {[Store].[USA].[CA].[Beverly Hills], [Time].[1997]}
          {[Store].[USA].[CA].[San Diego], [Time].[1997]}
          {[Store].[USA].[CA].[Los Angeles], [Time].[1997]}
          {[Store].[USA].[WA].[Walla Walla], [Time].[1997]}
          {[Store].[USA].[WA].[Bellingham], [Time].[1997]}
          {[Store].[USA].[WA].[Yakima], [Time].[1997]}
          {[Store].[USA].[WA].[Spokane], [Time].[1997]}
          {[Store].[USA].[WA].[Bremerton], [Time].[1997]}
          {[Store].[USA].[WA].[Seattle], [Time].[1997]}
          {[Store].[USA].[WA].[Tacoma], [Time].[1997]}
          Row #0: 2,173
          Row #0: 2,933
          Row #0: 26,079
          Row #1: 3,465
          Row #1: 5,891
          Row #1: 41,580
          Row #2: 3,465
          Row #2: 5,891
          Row #2: 41,580
          Row #3: 176
          Row #3: 222
          Row #3: 2,117
          Row #4: 1,778
          Row #4: 2,545
          Row #4: 21,333
          Row #5: 2,136
          Row #5: 2,686
          Row #5: 25,635
          Row #6: 2,139
          Row #6: 2,669
          Row #6: 25,663
          Row #7: 184
          Row #7: 301
          Row #7: 2,203
          Row #8: 186
          Row #8: 275
          Row #8: 2,237
          Row #9: 958
          Row #9: 1,163
          Row #9: 11,491
          Row #10: 1,966
          Row #10: 2,634
          Row #10: 23,591
          Row #11: 2,048
          Row #11: 2,623
          Row #11: 24,576
          Row #12: 2,084
          Row #12: 2,304
          Row #12: 25,011
          Row #13: 2,938
          Row #13: 3,818
          Row #13: 35,257
        RESULT
    end

    # Java: FunctionTest#testOrderEmpty
    it "sorts an empty set" do
      assert_query_returns @olap,
        "select \n" \
        "  Order(" \
        "    {}," \
        "    [Customers].currentMember, BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
        RESULT
    end

    # Java: FunctionTest#testOrderOne
    it "sorts a single member set" do
      assert_query_returns @olap,
        "select \n" \
        "  Order(" \
        "    {[Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]}," \
        "    [Customers].currentMember, BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          Row #0: 75
        RESULT
    end

    # Java: FunctionTest#testOrderKeyEmpty
    it "sorts an empty set by OrderKey" do
      assert_query_returns @olap,
        "select \n" \
        "  Order(" \
        "    {}," \
        "    [Customers].currentMember.OrderKey, BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
        RESULT
    end

    # Java: FunctionTest#testOrderKeyOne
    it "sorts a single member set by OrderKey" do
      assert_query_returns @olap,
        "select \n" \
        "  Order(" \
        "    {[Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]}," \
        "    [Customers].currentMember.OrderKey, BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          Row #0: 75
        RESULT
    end

    # Java: FunctionTest#testOrderDesc
    it "sorts by member name DESC" do
      # Based on olap4j's OlapTest.testSortDimension
      assert_query_returns @olap,
        "SELECT\n" \
        "{[Measures].[Store Sales]} ON COLUMNS,\n" \
        "{Order(\n" \
        "  {{[Product].[Drink], [Product].[Drink].Children}},\n" \
        "  [Product].CurrentMember.Name,\n" \
        "  DESC)} ON ROWS\n" \
        "FROM [Sales]\n" \
        "WHERE {[Time].[1997].[Q3].[7]}",
        <<~RESULT
          Axis #0:
          {[Time].[1997].[Q3].[7]}
          Axis #1:
          {[Measures].[Store Sales]}
          Axis #2:
          {[Product].[Drink]}
          {[Product].[Drink].[Dairy]}
          {[Product].[Drink].[Beverages]}
          {[Product].[Drink].[Alcoholic Beverages]}
          Row #0: 4,409.58
          Row #1: 629.69
          Row #2: 2,477.02
          Row #3: 1,302.87
        RESULT
    end

    # Java: FunctionTest#testOrderMemberMemberValueExpNew
    it "sorts by OrderKey BDESC with CompareSiblingsByOrderKey" do
      with_properties(CompareSiblingsByOrderKey: true) do
        # Use a fresh connection to make sure bad member ordinals haven't
        # been assigned by previous tests.
        Mondrian::OLAP::Connection.flush_schema_cache
        olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
        begin
          assert_query_returns olap,
            "select \n" \
            "  Order(" \
            "    {[Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
            "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
            "    [Customers].currentMember.OrderKey, BDESC) \n" \
            "on 0 from [Sales]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
              {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
              Row #0: 33
              Row #0: 75
            RESULT
        ensure
          olap.close
          Mondrian::OLAP::Connection.flush_schema_cache
        end
      end
    end

    # Java: FunctionTest#testOrderMemberMemberValueExpNew1
    it "sorts by default measure BDESC with CompareSiblingsByOrderKey" do
      # Sort by default measure
      with_properties(CompareSiblingsByOrderKey: true) do
        # Use a fresh connection to make sure bad member ordinals haven't
        # been assigned by previous tests.
        Mondrian::OLAP::Connection.flush_schema_cache
        olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
        begin
          assert_query_returns olap,
            "select \n" \
            "  Order(" \
            "    {[Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
            "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
            "    [Customers].currentMember, BDESC) \n" \
            "on 0 from [Sales]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
              {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
              Row #0: 75
              Row #0: 33
            RESULT
        ensure
          olap.close
          Mondrian::OLAP::Connection.flush_schema_cache
        end
      end
    end

    # Java: FunctionTest#testOrderMemberDefaultFlag1
    it "defaults to ASC when flags not specified, sorting by OrderKey" do
      # Flags not specified default to ASC - sort by default measure
      assert_query_returns @olap,
        "with \n" \
        "  Member [Measures].[Zero] as '0' \n" \
        "select \n" \
        "  Order(" \
        "    {[Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
        "    [Customers].currentMember.OrderKey) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          Row #0: 33
          Row #0: 75
        RESULT
    end

    # Java: FunctionTest#testOrderMemberDefaultFlag2
    it "defaults to ASC when flags not specified, sorting by measure" do
      # Flags not specified default to ASC
      assert_query_returns @olap,
        "with \n" \
        "  Member [Measures].[Zero] as '0' \n" \
        "select \n" \
        "  Order(" \
        "    {[Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
        "    [Measures].[Store Cost]) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          Row #0: 75
          Row #0: 33
        RESULT
    end

    # Java: FunctionTest#testOrderMemberMemberValueExpHierarchy
    it "sorts by OrderKey DESC respecting hierarchy order" do
      # Santa Monica and Woodland Hills both don't have orderkey
      # Members are sorted by the order of their keys
      assert_query_returns @olap,
        "select \n" \
        "  Order(" \
        "    {[Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
        "    [Customers].currentMember.OrderKey, DESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          Row #0: 75
          Row #0: 33
        RESULT
    end

    # Java: FunctionTest#testOrderMemberMultiKeysMemberValueExp1
    it "sorts by unit sales then customer id with multiple keys" do
      # Sort by unit sales and then customer id (Adeline = 6442, Abe = 570)
      assert_query_returns @olap,
        "select \n" \
        "  Order(" \
        "    {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]," \
        "     [Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
        "    [Measures].[Unit Sales], BDESC, [Customers].currentMember.OrderKey, BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]}
          Row #0: 75
          Row #0: 33
          Row #0: 33
        RESULT
    end

    # Java: FunctionTest#testOrderMemberMultiKeysMemberValueExp2
    it "sorts by parent OrderKey then customer OrderKey with CompareSiblingsByOrderKey" do
      with_properties(CompareSiblingsByOrderKey: true) do
        # Use a fresh connection to make sure bad member ordinals haven't
        # been assigned by previous tests.
        Mondrian::OLAP::Connection.flush_schema_cache
        olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
        begin
          assert_query_returns olap,
            "select \n" \
            "  Order(" \
            "    {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]," \
            "     [Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
            "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
            "    [Customers].currentMember.Parent.Parent.OrderKey, BASC, [Customers].currentMember.OrderKey, BDESC) \n" \
            "on 0 from [Sales]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
              {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
              {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]}
              Row #0: 33
              Row #0: 75
              Row #0: 33
            RESULT
        ensure
          olap.close
          Mondrian::OLAP::Connection.flush_schema_cache
        end
      end
    end

    # Java: FunctionTest#testOrderMemberMultiKeysMemberValueExpDepends
    it "preserves order with dependent second key" do
      # Should preserve order of Abe and Adeline (note second key is [Time])
      assert_query_returns @olap,
        "select \n" \
        "  Order(" \
        "    {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]," \
        "     [Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
        "    [Measures].[Unit Sales], BDESC, [Time].[Time].currentMember, BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]}
          {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          Row #0: 75
          Row #0: 33
          Row #0: 33
        RESULT
    end

    # Java: FunctionTest#testOrderTupleSingleKeysNew
    it "sorts tuples by customer OrderKey BDESC with CompareSiblingsByOrderKey" do
      # Known Java-side failure: the Java test expects Woodland Hills before
      # Abe Tramel, but actual output has them swapped.
      skip "Known Java-side failure (testOrderTupleSingleKeysNew)"
    end

    # Java: FunctionTest#testOrderTupleSingleKeysNew1
    it "sorts tuples by store OrderKey DESC with CompareSiblingsByOrderKey" do
      with_properties(CompareSiblingsByOrderKey: true) do
        # Use a fresh connection to make sure bad member ordinals haven't
        # been assigned by previous tests.
        Mondrian::OLAP::Connection.flush_schema_cache
        olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
        begin
          assert_query_returns olap,
            "with \n" \
            "  set [NECJ] as \n" \
            "    'NonEmptyCrossJoin( \n" \
            "    {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]," \
            "     [Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
            "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
            "    {[Store].[USA].[WA].[Seattle],\n" \
            "     [Store].[USA].[CA],\n" \
            "     [Store].[USA].[OR]})'\n" \
            "select \n" \
            " Order([NECJ], [Store].currentMember.OrderKey, DESC) \n" \
            "on 0 from [Sales]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Customers].[USA].[WA].[Issaquah].[Abe Tramel], [Store].[USA].[WA].[Seattle]}
              {[Customers].[USA].[CA].[Woodland Hills].[Abel Young], [Store].[USA].[CA]}
              {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun], [Store].[USA].[CA]}
              Row #0: 33
              Row #0: 75
              Row #0: 33
            RESULT
        ensure
          olap.close
          Mondrian::OLAP::Connection.flush_schema_cache
        end
      end
    end

    # Java: FunctionTest#testOrderTupleMultiKeys1
    it "sorts tuples by multiple keys: store OrderKey then unit sales" do
      assert_query_returns @olap,
        "with \n" \
        "  set [NECJ] as \n" \
        "    'NonEmptyCrossJoin( \n" \
        "    {[Store].[USA].[CA],\n" \
        "     [Store].[USA].[WA]},\n" \
        "    {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]," \
        "     [Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]})' \n" \
        "select \n" \
        " Order([NECJ], [Store].currentMember.OrderKey, BDESC, [Measures].[Unit Sales], BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA], [Customers].[USA].[WA].[Issaquah].[Abe Tramel]}
          {[Store].[USA].[CA], [Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          {[Store].[USA].[CA], [Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          Row #0: 33
          Row #0: 75
          Row #0: 33
        RESULT
    end

    # Java: FunctionTest#testOrderTupleMultiKeys2
    it "sorts tuples by unit sales then customer ancestor OrderKey" do
      assert_query_returns @olap,
        "with \n" \
        "  set [NECJ] as \n" \
        "    'NonEmptyCrossJoin( \n" \
        "    {[Store].[USA].[CA],\n" \
        "     [Store].[USA].[WA]},\n" \
        "    {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]," \
        "     [Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]})' \n" \
        "select \n" \
        " Order([NECJ], [Measures].[Unit Sales], BDESC, Ancestor([Customers].currentMember, [Customers].[Name])" \
        ".OrderKey, BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[CA], [Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          {[Store].[USA].[CA], [Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          {[Store].[USA].[WA], [Customers].[USA].[WA].[Issaquah].[Abe Tramel]}
          Row #0: 75
          Row #0: 33
          Row #0: 33
        RESULT
    end

    # Java: FunctionTest#testOrderTupleMultiKeys3
    it "sorts tuples by unit sales DESC then customer ancestor BDESC" do
      # WA unit sales is greater than CA unit sales
      # Santa Monica unit sales (2660) is greater that Woodland hills (2516)
      assert_query_returns @olap,
        "with \n" \
        "  set [NECJ] as \n" \
        "    'NonEmptyCrossJoin( \n" \
        "    {[Store].[USA].[CA],\n" \
        "     [Store].[USA].[WA]},\n" \
        "    {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]," \
        "     [Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]})' \n" \
        "select \n" \
        " Order([NECJ], [Measures].[Unit Sales], DESC, Ancestor([Customers].currentMember, [Customers].[Name]), " \
        "BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Store].[USA].[WA], [Customers].[USA].[WA].[Issaquah].[Abe Tramel]}
          {[Store].[USA].[CA], [Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          {[Store].[USA].[CA], [Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          Row #0: 33
          Row #0: 33
          Row #0: 75
        RESULT
    end

    # Java: FunctionTest#testOrderTupleMultiKeyswithVCube
    it "sorts tuples with multiple keys on a virtual cube" do
      # Known Java-side failure: ordering of Abel Young and Abe Tramel differs
      # from expected.
      skip "Known Java-side failure (testOrderTupleMultiKeyswithVCube)"
    end

    # Java: FunctionTest#testOrderConstant1
    it "sorts by constant key then customer OrderKey" do
      # Sort by customerId (Abel = 7851, Adeline = 6442, Abe = 570)
      assert_query_returns @olap,
        "select \n" \
        "  Order(" \
        "    {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]," \
        "     [Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
        "    [Customers].[USA].OrderKey, BDESC, [Customers].currentMember.OrderKey, BASC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]}
          {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          Row #0: 33
          Row #0: 33
          Row #0: 75
        RESULT
    end

    # Java: FunctionTest#testOrderDiffrentDim
    it "sorts by keys from different dimensions" do
      assert_query_returns @olap,
        "select \n" \
        "  Order(" \
        "    {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]," \
        "     [Customers].[All Customers].[USA].[CA].[Woodland Hills].[Abel Young]," \
        "     [Customers].[All Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}," \
        "    [Product].currentMember.OrderKey, BDESC, [Gender].currentMember.OrderKey, BDESC) \n" \
        "on 0 from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Customers].[USA].[WA].[Issaquah].[Abe Tramel]}
          {[Customers].[USA].[CA].[Woodland Hills].[Abel Young]}
          {[Customers].[USA].[CA].[Santa Monica].[Adeline Chun]}
          Row #0: 33
          Row #0: 75
          Row #0: 33
        RESULT
    end
  end

  describe "Unorder" do
    # Java: FunctionTest#testUnorder
    it "removes ordering guarantees from sets" do
      assert_axis_returns @olap,
        "Unorder([Gender].members)",
        <<~EXPECTED.chomp
          [Gender].[All Gender]
          [Gender].[F]
          [Gender].[M]
        EXPECTED

      assert_axis_returns @olap,
        "Unorder(Order([Gender].members, -[Measures].[Unit Sales]))",
        <<~EXPECTED.chomp
          [Gender].[All Gender]
          [Gender].[M]
          [Gender].[F]
        EXPECTED

      assert_axis_returns @olap,
        "Unorder(Crossjoin([Gender].members, [Marital Status].Children))",
        <<~EXPECTED.chomp
          {[Gender].[All Gender], [Marital Status].[M]}
          {[Gender].[All Gender], [Marital Status].[S]}
          {[Gender].[F], [Marital Status].[M]}
          {[Gender].[F], [Marital Status].[S]}
          {[Gender].[M], [Marital Status].[M]}
          {[Gender].[M], [Marital Status].[S]}
        EXPECTED

      # Implicitly convert member to set
      assert_axis_returns @olap,
        "Unorder([Gender].[M])",
        "[Gender].[M]"
    end

    # Java: FunctionTest#testUnorder (error cases)
    it "raises error for invalid Unorder arguments" do
      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute("SELECT {Unorder(1 + 3)} ON 0 FROM [Sales]")
      end
      assert_match(/No function matches signature 'Unorder\(<Numeric Expression>\)'/, root_cause_message(error))

      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute("SELECT {Unorder([Gender].[M], 1 + 3)} ON 0 FROM [Sales]")
      end
      assert_match(/No function matches signature 'Unorder\(<Member>, <Numeric Expression>\)'/, root_cause_message(error))
    end

    # Java: FunctionTest#testUnorder (query form)
    it "works in a full query with measures on columns" do
      assert_query_returns @olap,
        "select {[Measures].[Store Sales], [Measures].[Unit Sales]} on 0,\n" \
        "  Unorder([Gender].Members) on 1\n" \
        "from [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Store Sales]}
          {[Measures].[Unit Sales]}
          Axis #2:
          {[Gender].[All Gender]}
          {[Gender].[F]}
          {[Gender].[M]}
          Row #0: 565,238.13
          Row #0: 266,773
          Row #1: 280,226.21
          Row #1: 131,558
          Row #2: 285,011.92
          Row #2: 135,215
        RESULT
    end
  end

  describe "ToggleDrillState" do
    # Java: FunctionTest#testToggleDrillState
    it "drills down on a member in the set" do
      assert_axis_returns @olap,
        "ToggleDrillState({[Customers].[USA],[Customers].[Canada]}," \
        "{[Customers].[USA],[Customers].[USA].[CA]})",
        <<~EXPECTED.chomp
          [Customers].[USA]
          [Customers].[USA].[CA]
          [Customers].[USA].[OR]
          [Customers].[USA].[WA]
          [Customers].[Canada]
        EXPECTED
    end

    # Java: FunctionTest#testToggleDrillState2
    it "drills down on Snack Foods within product departments" do
      assert_axis_returns @olap,
        "ToggleDrillState([Product].[Product Department].members, " \
        "{[Product].[All Products].[Food].[Snack Foods]})",
        <<~EXPECTED.chomp
          [Product].[Drink].[Alcoholic Beverages]
          [Product].[Drink].[Beverages]
          [Product].[Drink].[Dairy]
          [Product].[Food].[Baked Goods]
          [Product].[Food].[Baking Goods]
          [Product].[Food].[Breakfast Foods]
          [Product].[Food].[Canned Foods]
          [Product].[Food].[Canned Products]
          [Product].[Food].[Dairy]
          [Product].[Food].[Deli]
          [Product].[Food].[Eggs]
          [Product].[Food].[Frozen Foods]
          [Product].[Food].[Meat]
          [Product].[Food].[Produce]
          [Product].[Food].[Seafood]
          [Product].[Food].[Snack Foods]
          [Product].[Food].[Snack Foods].[Snack Foods]
          [Product].[Food].[Snacks]
          [Product].[Food].[Starchy Foods]
          [Product].[Non-Consumable].[Carousel]
          [Product].[Non-Consumable].[Checkout]
          [Product].[Non-Consumable].[Health and Hygiene]
          [Product].[Non-Consumable].[Household]
          [Product].[Non-Consumable].[Periodicals]
        EXPECTED
    end

    # Java: FunctionTest#testToggleDrillState3
    it "drills up when children are already present" do
      assert_axis_returns @olap,
        "ToggleDrillState(" \
        "{[Time].[1997].[Q1]," \
        " [Time].[1997].[Q2]," \
        " [Time].[1997].[Q2].[4]," \
        " [Time].[1997].[Q2].[6]," \
        " [Time].[1997].[Q3]}," \
        "{[Time].[1997].[Q2]})",
        <<~EXPECTED.chomp
          [Time].[1997].[Q1]
          [Time].[1997].[Q2]
          [Time].[1997].[Q3]
        EXPECTED
    end

    # Java: FunctionTest#testToggleDrillStateTuple
    # Bug 634860
    it "drills down on a tuple set" do
      assert_axis_returns @olap,
        "ToggleDrillState(\n" \
        "{([Store].[USA].[CA]," \
        "  [Product].[All Products].[Drink].[Alcoholic Beverages]),\n" \
        " ([Store].[USA]," \
        "  [Product].[All Products].[Drink])},\n" \
        "{[Store].[All stores].[USA].[CA]})",
        <<~EXPECTED.chomp
          {[Store].[USA].[CA], [Product].[Drink].[Alcoholic Beverages]}
          {[Store].[USA].[CA].[Alameda], [Product].[Drink].[Alcoholic Beverages]}
          {[Store].[USA].[CA].[Beverly Hills], [Product].[Drink].[Alcoholic Beverages]}
          {[Store].[USA].[CA].[Los Angeles], [Product].[Drink].[Alcoholic Beverages]}
          {[Store].[USA].[CA].[San Diego], [Product].[Drink].[Alcoholic Beverages]}
          {[Store].[USA].[CA].[San Francisco], [Product].[Drink].[Alcoholic Beverages]}
          {[Store].[USA], [Product].[Drink]}
        EXPECTED
    end

    # Java: FunctionTest#testToggleDrillStateRecursive
    it "raises error when RECURSIVE is used" do
      # We expect this to fail.
      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute(
          "Select \n" \
          "    ToggleDrillState(\n" \
          "        {[Store].[USA]}, \n" \
          "        {[Store].[USA]}, recursive) on Axis(0) \n" \
          "from [Sales]\n"
        )
      end
      assert root_cause_message(error).include?("'RECURSIVE' is not supported in ToggleDrillState."),
        "Expected error about RECURSIVE not supported, got: #{root_cause_message(error)}"
    end
  end
end
