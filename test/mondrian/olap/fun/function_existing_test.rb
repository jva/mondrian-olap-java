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
describe "Exists and Existing" do
  before(:all) do
    create_olap_connection
  end

  describe "Exists" do
    # Java: FunctionTest#testExistsMembersAll
    it "filters members keeping those that exist with All member" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists(
          {[Customers].[All Customers],
           [Customers].[Country].Members,
           [Customers].[State Province].[CA],
           [Customers].[Canada].[BC].[Richmond]},
          {[Customers].[All Customers]})
        on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[All Customers]}
        {[Customers].[Canada]}
        {[Customers].[Mexico]}
        {[Customers].[USA]}
        {[Customers].[USA].[CA]}
        {[Customers].[Canada].[BC].[Richmond]}
        Row #0: 266,773
        Row #0:
        Row #0:
        Row #0: 266,773
        Row #0: 74,748
        Row #0:
      RESULT
    end

    # Java: FunctionTest#testExistsMembersLevel2
    it "filters members keeping those that exist with USA member" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists(
          {[Customers].[All Customers],
           [Customers].[Country].Members,
           [Customers].[State Province].[CA],
           [Customers].[Canada].[BC].[Richmond]},
          {[Customers].[Country].[USA]})
        on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[All Customers]}
        {[Customers].[USA]}
        {[Customers].[USA].[CA]}
        Row #0: 266,773
        Row #0: 266,773
        Row #0: 74,748
      RESULT
    end

    # Java: FunctionTest#testExistsWithImplicitAllMember
    it "returns full tuple list when second arg implies All member" do
      # The tuple in the second arg in this case should implicitly
      # contain [Customers].[All Customers], so the whole tuple list
      # from the first arg should be returned.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select non empty exists(
          {[Customers].[All Customers],
           [Customers].[All Customers].Children,
           [Customers].[State Province].Members},
          {[Product].Members})
        on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[All Customers]}
        {[Customers].[USA]}
        {[Customers].[USA].[CA]}
        {[Customers].[USA].[OR]}
        {[Customers].[USA].[WA]}
        Row #0: 266,773
        Row #0: 266,773
        Row #0: 74,748
        Row #0: 67,659
        Row #0: 124,366
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists( [Customers].[USA].[CA], (Store.[USA], Gender.[F])) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[USA].[CA]}
        Row #0: 74,748
      RESULT
    end

    # Java: FunctionTest#testExistsWithMultipleHierarchies
    it "handles queries with a multi-hierarchy dimension in either or both args" do
      # Tests queries w/ a multi-hierarchy dim in either or both args.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists( crossjoin( time.[1997], {[Time.Weekly].[1997].[16]}), { Gender.F } ) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997], [Time.Weekly].[1997].[16]}
        Row #0: 3,839
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists( time.[1997].[Q1], {[Time.Weekly].[1997].[4]}) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1997].[Q1]}
        Row #0: 66,291
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists( { Gender.F }, crossjoin( time.[1997], {[Time.Weekly].[1997].[16]}) ) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Gender].[F]}
        Row #0: 131,558
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists( { time.[1998] }, crossjoin( time.[1997], {[Time.Weekly].[1997].[16]}) ) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
      RESULT
    end

    # Java: FunctionTest#testExistsWithDefaultNonAllMember
    it "handles exists with non-all default member on Time hierarchy" do
      # Default mem for Time is 1997

      # Non-all default on right side.
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists( [Time].[1998].[Q1], Gender.[All Gender]) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
      RESULT

      # Switching to an explicit member on the hierarchy chain should return
      # 1998.Q1
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists( [Time].[1998].[Q1], ([Time].[1998], Gender.[All Gender])) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1998].[Q1]}
        Row #0:
      RESULT

      # Non-all default on left side
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists( Gender.[All Gender], (Gender.[F], [Time].[1998].[Q1])) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists( (Time.[1998].[Q1].[1], Gender.[All Gender]), (Gender.[F], [Time].[1998].[Q1])) on 0 from sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Time].[1998].[Q1].[1], [Gender].[All Gender]}
        Row #0:
      RESULT
    end

    # Java: FunctionTest#testExistsMembers2Hierarchies
    it "filters members with two hierarchy filter tuples" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists(
          {[Customers].[All Customers],
           [Customers].[All Customers].Children,
           [Customers].[State Province].Members,
           [Customers].[Country].[Canada],
           [Customers].[Country].[Mexico]},
          {[Customers].[Country].[USA],
           [Customers].[State Province].[Veracruz]})
        on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[All Customers]}
        {[Customers].[Mexico]}
        {[Customers].[USA]}
        {[Customers].[Mexico].[Veracruz]}
        {[Customers].[USA].[CA]}
        {[Customers].[USA].[OR]}
        {[Customers].[USA].[WA]}
        {[Customers].[Mexico]}
        Row #0: 266,773
        Row #0:
        Row #0: 266,773
        Row #0:
        Row #0: 74,748
        Row #0: 67,659
        Row #0: 124,366
        Row #0:
      RESULT
    end

    # Java: FunctionTest#testExistsTuplesAll
    it "filters tuples keeping those that exist with All member" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists(
          crossjoin({[Product].[All Products]},{[Customers].[All Customers]}),
          {[Customers].[All Customers]})
        on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Product].[All Products], [Customers].[All Customers]}
        Row #0: 266,773
      RESULT
    end

    # Java: FunctionTest#testExistsTuplesLevel2
    it "filters tuples keeping those that exist with USA member" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists(
          crossjoin({[Product].[All Products]},{[Customers].[All Customers].Children}),
          {[Customers].[All Customers].[USA]})
        on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Product].[All Products], [Customers].[USA]}
        Row #0: 266,773
      RESULT
    end

    # Java: FunctionTest#testExistsTuplesLevel23
    it "filters state province tuples keeping those under USA" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists(
          crossjoin({[Customers].[State Province].Members}, {[Product].[All Products]}),
          {[Customers].[All Customers].[USA]})
        on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[USA].[CA], [Product].[All Products]}
        {[Customers].[USA].[OR], [Product].[All Products]}
        {[Customers].[USA].[WA], [Product].[All Products]}
        Row #0: 74,748
        Row #0: 67,659
        Row #0: 124,366
      RESULT
    end

    # Java: FunctionTest#testExistsTuples2Dim
    it "filters tuples from two dimensions keeping those that exist with Dairy and USA" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists(
          crossjoin({[Customers].[State Province].Members}, {[Product].[Product Family].Members}),
          {([Product].[Product Department].[Dairy],[Customers].[All Customers].[USA])})
        on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[USA].[CA], [Product].[Drink]}
        {[Customers].[USA].[OR], [Product].[Drink]}
        {[Customers].[USA].[WA], [Product].[Drink]}
        Row #0: 7,102
        Row #0: 6,106
        Row #0: 11,389
      RESULT
    end

    # Java: FunctionTest#testExistsTuplesDiffDim
    it "filters tuples across different dimensions with Promotions in filter" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        select exists(
          crossjoin(
            crossjoin({[Customers].[State Province].Members},
                      {[Time].[Year].[1997]}),
            {[Product].[Product Family].Members}),
          {([Product].[Product Department].[Dairy],
            [Promotions].[All Promotions],
            [Customers].[All Customers].[USA])})
        on 0 from Sales
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Customers].[USA].[CA], [Time].[1997], [Product].[Drink]}
        {[Customers].[USA].[OR], [Time].[1997], [Product].[Drink]}
        {[Customers].[USA].[WA], [Time].[1997], [Product].[Drink]}
        Row #0: 7,102
        Row #0: 6,106
        Row #0: 11,389
      RESULT
    end
  end

  describe "Existing" do
    # Java: FunctionTest#testExisting
    it "filters set to current context using Existing keyword" do
      # Basic test
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
          member measures.ExistingCount as
          count(Existing [Product].[Product Subcategory].Members)
          select {measures.ExistingCount} on 0,
          [Product].[Product Family].Members on 1
          from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[ExistingCount]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        Row #0: 8
        Row #1: 62
        Row #2: 32
      RESULT

      # Same as exists+currentMember
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with member measures.StaticCount as
          count([Product].[Product Subcategory].Members)
          member measures.WithExisting as
          count(Existing [Product].[Product Subcategory].Members)
          member measures.WithExists as
          count(Exists([Product].[Product Subcategory].Members, [Product].CurrentMember))
          select {measures.StaticCount, measures.WithExisting, measures.WithExists} on 0,
          [Product].[Product Family].Members on 1
          from [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[StaticCount]}
        {[Measures].[WithExisting]}
        {[Measures].[WithExists]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        Row #0: 102
        Row #0: 8
        Row #0: 8
        Row #1: 102
        Row #1: 62
        Row #1: 62
        Row #2: 102
        Row #2: 32
        Row #2: 32
      RESULT
    end

    # Java: FunctionTest#testExistingCalculatedMeasure
    it "uses Existing in a calculated measure with Time.Weekly" do
      # Sorry about the mess, this came from Analyzer
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH
        SET [*NATIVE_CJ_SET] AS 'FILTER({[Time.Weekly].[All Time.Weeklys].[1997].[2],[Time.Weekly].[All Time.Weeklys].[1997].[24]}, NOT ISEMPTY ([Measures].[Store Sales]) OR NOT ISEMPTY ([Measures].[CALCULATED_MEASURE_1]))'
        SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Time.Weekly].CURRENTMEMBER.ORDERKEY,BASC,ANCESTOR([Time.Weekly].CURRENTMEMBER,[Time.Weekly].[Year]).ORDERKEY,BASC)'
        SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0],[Measures].[CALCULATED_MEASURE_1]}'
        SET [*BASE_MEMBERS__Time.Weekly_] AS '{[Time.Weekly].[All Time.Weeklys].[1997].[2],[Time.Weekly].[All Time.Weeklys].[1997].[24]}'
        SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Time.Weekly].CURRENTMEMBER)})'
        MEMBER [Measures].[CALCULATED_MEASURE_1] AS 'SetToStr( EXISTING [Time.Weekly].[Week].Members )'
        MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Store Sales]', FORMAT_STRING = '#,###.00', SOLVE_ORDER=500
        SELECT
        [*BASE_MEMBERS__Measures_] ON COLUMNS
        , NON EMPTY
        [*SORTED_ROW_AXIS] ON ROWS
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[*FORMATTED_MEASURE_0]}
        {[Measures].[CALCULATED_MEASURE_1]}
        Axis #2:
        {[Time.Weekly].[1997].[2]}
        {[Time.Weekly].[1997].[24]}
        Row #0: 19,756.43
        Row #0: {[Time.Weekly].[1997].[2]}
        Row #1: 11,371.84
        Row #1: {[Time.Weekly].[1997].[24]}
      RESULT
    end

    # Java: FunctionTest#testExistingCalculatedMeasureCompoundSlicer
    it "uses Existing with compound slicer on Product" do
      # Basic test
      assert_query_returns @olap, <<~MDX, <<~RESULT
        with
          member measures.subcategorystring as SetToStr( EXISTING [Product].[Product Subcategory].Members)
          select { measures.subcategorystring } on 0
          from [Sales]
          where {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine]}
      MDX
        Axis #0:
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine]}
        Axis #1:
        {[Measures].[subcategorystring]}
        Row #0: {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Wine]}
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        with MEMBER [Measures].[*CALCULATED_MEASURE_1] AS 'SetToStr( EXISTING [Product].[Product Category].Members )'
         SELECT {[Measures].[*CALCULATED_MEASURE_1]} ON COLUMNS
         FROM [Sales]
         WHERE {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer], [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Wine], [Product].[Food].[Eggs].[Eggs] }
      MDX
        Axis #0:
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer]}
        {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Wine]}
        {[Product].[Food].[Eggs].[Eggs]}
        Axis #1:
        {[Measures].[*CALCULATED_MEASURE_1]}
        Row #0: {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Product].[Food].[Eggs].[Eggs]}
      RESULT
    end

    # Java: FunctionTest#testExistingAggSet
    it "aggregates an Existing simple set" do
      # Aggregate simple set
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Measures].[Edible Sales] AS
        Aggregate( Existing {[Product].[Drink], [Product].[Food]}, Measures.[Unit Sales] )
        SELECT {Measures.[Unit Sales], Measures.[Edible Sales]} ON 0,
        { [Product].[Product Family].Members, [Product].[All Products] } ON 1
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Edible Sales]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        {[Product].[All Products]}
        Row #0: 24,597
        Row #0: 24,597
        Row #1: 191,940
        Row #1: 191,940
        Row #2: 50,236
        Row #2:
        Row #3: 266,773
        Row #3: 216,537
      RESULT
    end

    # Java: FunctionTest#testExistingGenerateAgg
    it "uses Generate to override Existing context for top brand aggregation" do
      # Generate overrides existing context
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH SET BestOfFamilies AS
          Generate( [Product].[Product Family].Members,
                    TopCount( Existing [Product].[Brand Name].Members, 10, Measures.[Unit Sales]) )
        MEMBER Measures.[Top 10 Brand Sales] AS Aggregate(Existing BestOfFamilies, Measures.[Unit Sales])
        MEMBER Measures.[Rest Brand Sales] AS Aggregate( Except(Existing [Product].[Brand Name].Members, Existing BestOfFamilies), Measures.[Unit Sales])
        SELECT { Measures.[Unit Sales], Measures.[Top 10 Brand Sales], Measures.[Rest Brand Sales] } ON 0,
               {[Product].[Product Family].Members} ON 1
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Unit Sales]}
        {[Measures].[Top 10 Brand Sales]}
        {[Measures].[Rest Brand Sales]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        Row #0: 24,597
        Row #0: 9,448
        Row #0: 15,149
        Row #1: 191,940
        Row #1: 32,506
        Row #1: 159,434
        Row #2: 50,236
        Row #2: 8,936
        Row #2: 41,300
      RESULT
    end

    # Java: FunctionTest#testExistingGenerateOverrides
    it "Generate overrides Existing context so Non-Consumable departments appear for all families" do
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER Measures.[StaticSumNC] AS
         'Sum(Generate([Product].[Non-Consumable],    Existing [Product].[Product Department].Members), Measures.[Unit Sales])'
        SELECT { Measures.[StaticSumNC], Measures.[Unit Sales] } ON 0,
            NON EMPTY {[Product].[Product Family].Members} ON 1
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[StaticSumNC]}
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Product].[Drink]}
        {[Product].[Food]}
        {[Product].[Non-Consumable]}
        Row #0: 50,236
        Row #0: 24,597
        Row #1: 50,236
        Row #1: 191,940
        Row #2: 50,236
        Row #2: 50,236
      RESULT

      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER Measures.[StaticSumNC] AS
         'Sum(Generate([Product].[Product Family].Members,    Existing [Product].[Product Department].Members), Measures.[Unit Sales])'
        SELECT { Measures.[StaticSumNC], Measures.[Unit Sales] } ON 0,
            NON EMPTY {[Product].[Non-Consumable]} ON 1
        FROM [Sales]
      MDX
        Axis #0:
        {}
        Axis #1:
        {[Measures].[StaticSumNC]}
        {[Measures].[Unit Sales]}
        Axis #2:
        {[Product].[Non-Consumable]}
        Row #0: 266,773
        Row #0: 50,236
      RESULT
    end

    # Java: FunctionTest#testExistingVirtualCube
    it "uses Existing and Exists on Time.Weekly in a virtual cube" do
      # This should ideally return 14 for both,
      # but being coherent with exists is good enough
      assert_query_returns @olap, <<~MDX, <<~RESULT
        WITH MEMBER [Measures].[Count Exists] AS Count(exists( [Time.Weekly].[Week].Members, [Time.Weekly].CurrentMember ) )
         MEMBER [Measures].[Count Existing] AS Count(existing [Time.Weekly].[Week].Members)
        SELECT
        {[Measures].[Count Exists], [Measures].[Count Existing]}
        ON 0
        FROM [Warehouse and Sales]
        WHERE [Time].[1997].[Q2]
      MDX
        Axis #0:
        {[Time].[1997].[Q2]}
        Axis #1:
        {[Measures].[Count Exists]}
        {[Measures].[Count Existing]}
        Row #0: 104
        Row #0: 104
      RESULT
    end
  end
end
