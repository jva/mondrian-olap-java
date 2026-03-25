# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2002-2021 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/CachedExistsTest.java
describe "CachedExists" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Java: CachedExistsTest#testEducationLevelSubtotals
  it "education level subtotals" do
    mdx = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Education Level_],[*BASE_MEMBERS__Product_])'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Education Level].CURRENTMEMBER.ORDERKEY,BASC,[Measures].[*SORTED_MEASURE],BDESC)'
      SET [*BASE_MEMBERS__Education Level_] AS '{[Education Level].[All Education Levels].[Bachelors Degree],[Education Level].[All Education Levels].[Graduate Degree]}'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
      SET [*BASE_MEMBERS__Product_] AS '{[Product].[All Products].[Drink],[Product].[All Products].[Food]}'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Education Level].CURRENTMEMBER,[Product].CURRENTMEMBER)})'
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
      MEMBER [Measures].[*SORTED_MEASURE] AS '([Measures].[*FORMATTED_MEASURE_0])', SOLVE_ORDER=400
      MEMBER [Product].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CachedExists([*CJ_ROW_AXIS], ([Education Level].CURRENTMEMBER), "*CJ_ROW_AXIS"))', SOLVE_ORDER=99
      SELECT [*BASE_MEMBERS__Measures_] ON COLUMNS, NON EMPTY UNION(CROSSJOIN(GENERATE([*CJ_ROW_AXIS], {([Education Level].CURRENTMEMBER)}),{[Product].[*TOTAL_MEMBER_SEL~SUM]}),[*SORTED_ROW_AXIS]) ON ROWS
      FROM [Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Education Level].[Bachelors Degree], [Product].[*TOTAL_MEMBER_SEL~SUM]}
      {[Education Level].[Graduate Degree], [Product].[*TOTAL_MEMBER_SEL~SUM]}
      {[Education Level].[Bachelors Degree], [Product].[Food]}
      {[Education Level].[Bachelors Degree], [Product].[Drink]}
      {[Education Level].[Graduate Degree], [Product].[Food]}
      {[Education Level].[Graduate Degree], [Product].[Drink]}
      Row #0: 55,788
      Row #1: 12,580
      Row #2: 49,365
      Row #3: 6,423
      Row #4: 11,255
      Row #5: 1,325
    RESULT
  end

  # Java: CachedExistsTest#testProductFamilySubtotals
  it "product family subtotals" do
    mdx = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'FILTER(FILTER([Product].[Product Department].MEMBERS,ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]) IN {[Product].[All Products].[Drink],[Product].[All Products].[Non-Consumable]}), NOT ISEMPTY ([Measures].[Unit Sales]))'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]).ORDERKEY,BASC,[Product].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
      SET [*BASE_MEMBERS__Product_] AS 'FILTER([Product].[Product Department].MEMBERS,ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]) IN {[Product].[All Products].[Drink],[Product].[All Products].[Non-Consumable]})'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Product].CURRENTMEMBER)})'
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
      MEMBER [Product].[All Products].[Drink].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CachedExists([*CJ_ROW_AXIS], ([Product].[All Products].[Drink]), "*CJ_ROW_AXIS"))', SOLVE_ORDER=100
      MEMBER [Product].[All Products].[Non-Consumable].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CachedExists([*CJ_ROW_AXIS], ([Product].[All Products].[Non-Consumable]), "*CJ_ROW_AXIS"))', SOLVE_ORDER=100
      SELECT
      [*BASE_MEMBERS__Measures_] ON COLUMNS
      , NON EMPTY
      UNION({[Product].[All Products].[Drink].[*TOTAL_MEMBER_SEL~SUM], [Product].[All Products].[Non-Consumable].[*TOTAL_MEMBER_SEL~SUM]},[*SORTED_ROW_AXIS]) ON ROWS
      FROM [Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Product].[Drink].[*TOTAL_MEMBER_SEL~SUM]}
      {[Product].[Non-Consumable].[*TOTAL_MEMBER_SEL~SUM]}
      {[Product].[Drink].[Alcoholic Beverages]}
      {[Product].[Drink].[Beverages]}
      {[Product].[Drink].[Dairy]}
      {[Product].[Non-Consumable].[Carousel]}
      {[Product].[Non-Consumable].[Checkout]}
      {[Product].[Non-Consumable].[Health and Hygiene]}
      {[Product].[Non-Consumable].[Household]}
      {[Product].[Non-Consumable].[Periodicals]}
      Row #0: 24,597
      Row #1: 50,236
      Row #2: 6,838
      Row #3: 13,573
      Row #4: 4,186
      Row #5: 841
      Row #6: 1,779
      Row #7: 16,284
      Row #8: 27,038
      Row #9: 4,294
    RESULT
  end

  # Java: CachedExistsTest#testProductFamilyProductDepartmentSubtotals
  it "product family and product department subtotals" do
    mdx = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Product_],[*BASE_MEMBERS__Gender_])'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]).ORDERKEY,BASC,[Product].CURRENTMEMBER.ORDERKEY,BASC,[Gender].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
      SET [*BASE_MEMBERS__Gender_] AS '[Gender].[Gender].MEMBERS'
      SET [*BASE_MEMBERS__Product_] AS 'FILTER([Product].[Product Department].MEMBERS,(ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]) IN {[Product].[All Products].[Drink],[Product].[All Products].[Non-Consumable]}) AND ([Product].CURRENTMEMBER IN {[Product].[All Products].[Drink].[Beverages],[Product].[All Products].[Drink].[Dairy],[Product].[All Products].[Non-Consumable].[Periodicals]}))'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Product].CURRENTMEMBER,[Gender].CURRENTMEMBER)})'
      MEMBER [Gender].[*DEFAULT_MEMBER] AS '[Gender].DEFAULTMEMBER', SOLVE_ORDER=-400
      MEMBER [Gender].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CachedExists([*CJ_ROW_AXIS], ([Product].CURRENTMEMBER), "*CJ_ROW_AXIS"))', SOLVE_ORDER=99
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
      MEMBER [Product].[All Products].[Drink].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CachedExists([*CJ_ROW_AXIS], ([Product].[All Products].[Drink]), "*CJ_ROW_AXIS"))', SOLVE_ORDER=100
      MEMBER [Product].[All Products].[Non-Consumable].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CachedExists([*CJ_ROW_AXIS], ([Product].[All Products].[Non-Consumable]), "*CJ_ROW_AXIS"))', SOLVE_ORDER=100
      SELECT
      [*BASE_MEMBERS__Measures_] ON COLUMNS
      , NON EMPTY
      UNION(CROSSJOIN(GENERATE([*CJ_ROW_AXIS], {([Product].CURRENTMEMBER)}),{[Gender].[*TOTAL_MEMBER_SEL~SUM]}),UNION(CROSSJOIN({[Product].[All Products].[Drink].[*TOTAL_MEMBER_SEL~SUM], [Product].[All Products].[Non-Consumable].[*TOTAL_MEMBER_SEL~SUM]},{([Gender].[*DEFAULT_MEMBER])}),[*SORTED_ROW_AXIS])) ON ROWS
      FROM [Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Product].[Drink].[Beverages], [Gender].[*TOTAL_MEMBER_SEL~SUM]}
      {[Product].[Drink].[Dairy], [Gender].[*TOTAL_MEMBER_SEL~SUM]}
      {[Product].[Non-Consumable].[Periodicals], [Gender].[*TOTAL_MEMBER_SEL~SUM]}
      {[Product].[Drink].[*TOTAL_MEMBER_SEL~SUM], [Gender].[*DEFAULT_MEMBER]}
      {[Product].[Non-Consumable].[*TOTAL_MEMBER_SEL~SUM], [Gender].[*DEFAULT_MEMBER]}
      {[Product].[Drink].[Beverages], [Gender].[F]}
      {[Product].[Drink].[Beverages], [Gender].[M]}
      {[Product].[Drink].[Dairy], [Gender].[F]}
      {[Product].[Drink].[Dairy], [Gender].[M]}
      {[Product].[Non-Consumable].[Periodicals], [Gender].[F]}
      {[Product].[Non-Consumable].[Periodicals], [Gender].[M]}
      Row #0: 13,573
      Row #1: 4,186
      Row #2: 4,294
      Row #3: 17,759
      Row #4: 4,294
      Row #5: 6,776
      Row #6: 6,797
      Row #7: 1,987
      Row #8: 2,199
      Row #9: 2,168
      Row #10: 2,126
    RESULT
  end

  # Java: CachedExistsTest#testRowColumSubtotals
  it "row and column subtotals" do
    mdx = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Time_],NONEMPTYCROSSJOIN([*BASE_MEMBERS__Product_],[*BASE_MEMBERS__Gender_]))'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Product].CURRENTMEMBER.ORDERKEY,BASC,[Gender].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*SORTED_COL_AXIS] AS 'ORDER([*CJ_COL_AXIS],ANCESTOR([Time].CURRENTMEMBER, [Time].[Year]).ORDERKEY,BASC,[Time].CURRENTMEMBER.ORDERKEY,BASC,[Measures].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
      SET [*BASE_MEMBERS__Gender_] AS '[Gender].[Gender].MEMBERS'
      SET [*CJ_COL_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Time].CURRENTMEMBER)})'
      SET [*BASE_MEMBERS__Product_] AS '{[Product].[All Products].[Drink],[Product].[All Products].[Non-Consumable]}'
      SET [*BASE_MEMBERS__Time_] AS '{[Time].[1997].[Q1],[Time].[1997].[Q2]}'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Product].CURRENTMEMBER,[Gender].CURRENTMEMBER)})'
      MEMBER [Gender].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CachedExists([*CJ_ROW_AXIS], ([Product].CURRENTMEMBER), "*CJ_ROW_AXIS"))', SOLVE_ORDER=99
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
      MEMBER [Time].[1997].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CachedExists([*CJ_COL_AXIS], ([Time].[1997]), "*CJ_COL_AXIS"))', SOLVE_ORDER=98
      SELECT
      UNION(CROSSJOIN({[Time].[1997].[*TOTAL_MEMBER_SEL~SUM]},[*BASE_MEMBERS__Measures_]),CROSSJOIN([*SORTED_COL_AXIS],[*BASE_MEMBERS__Measures_])) ON COLUMNS
      , NON EMPTY
      UNION(CROSSJOIN(GENERATE([*CJ_ROW_AXIS], {([Product].CURRENTMEMBER)}),{[Gender].[*TOTAL_MEMBER_SEL~SUM]}),[*SORTED_ROW_AXIS]) ON ROWS
      FROM [Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Time].[1997].[*TOTAL_MEMBER_SEL~SUM], [Measures].[*FORMATTED_MEASURE_0]}
      {[Time].[1997].[Q1], [Measures].[*FORMATTED_MEASURE_0]}
      {[Time].[1997].[Q2], [Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Product].[Drink], [Gender].[*TOTAL_MEMBER_SEL~SUM]}
      {[Product].[Non-Consumable], [Gender].[*TOTAL_MEMBER_SEL~SUM]}
      {[Product].[Drink], [Gender].[F]}
      {[Product].[Drink], [Gender].[M]}
      {[Product].[Non-Consumable], [Gender].[F]}
      {[Product].[Non-Consumable], [Gender].[M]}
      Row #0: 11,871
      Row #0: 5,976
      Row #0: 5,895
      Row #1: 24,396
      Row #1: 12,506
      Row #1: 11,890
      Row #2: 5,806
      Row #2: 2,934
      Row #2: 2,872
      Row #3: 6,065
      Row #3: 3,042
      Row #3: 3,023
      Row #4: 11,997
      Row #4: 6,144
      Row #4: 5,853
      Row #5: 12,399
      Row #5: 6,362
      Row #5: 6,037
    RESULT
  end

  # Java: CachedExistsTest#testProductFamilyDisplayMember
  it "product family display member" do
    mdx = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Product_],[*BASE_MEMBERS__Gender_])'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]).ORDERKEY,BASC,[Gender].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*NATIVE_MEMBERS__Product_] AS 'GENERATE([*NATIVE_CJ_SET], {[Product].CURRENTMEMBER})'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
      SET [*BASE_MEMBERS__Gender_] AS '[Gender].[Gender].MEMBERS'
      SET [*BASE_MEMBERS__Product_] AS 'FILTER([Product].[Product Category].MEMBERS,(ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]) IN {[Product].[All Products].[Drink],[Product].[All Products].[Non-Consumable]}) AND ([Product].CURRENTMEMBER IN {[Product].[All Products].[Non-Consumable].[Household].[Candles],[Product].[All Products].[Drink].[Dairy].[Dairy],[Product].[All Products].[Non-Consumable].[Periodicals].[Magazines],[Product].[All Products].[Drink].[Beverages].[Pure Juice Beverages]}))'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {(ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]).CALCULATEDCHILD("*DISPLAY_MEMBER"),[Gender].CURRENTMEMBER)})'
      MEMBER [Gender].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CachedExists([*CJ_ROW_AXIS], ([Product].CURRENTMEMBER), "*CJ_ROW_AXIS" ))', SOLVE_ORDER=99
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
      MEMBER [Product].[Drink].[*DISPLAY_MEMBER] AS 'AGGREGATE (FILTER([*NATIVE_MEMBERS__Product_],ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]) IS [Product].[All Products].[Drink]))', SOLVE_ORDER=-100
      MEMBER [Product].[Non-Consumable].[*DISPLAY_MEMBER] AS 'AGGREGATE (FILTER([*NATIVE_MEMBERS__Product_],ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]) IS [Product].[All Products].[Non-Consumable]))', SOLVE_ORDER=-100
      SELECT
      [*BASE_MEMBERS__Measures_] ON COLUMNS
      , NON EMPTY
      UNION(CROSSJOIN(GENERATE([*CJ_ROW_AXIS], {(ANCESTOR([Product].CURRENTMEMBER, [Product].[Product Family]))}),{[Gender].[*TOTAL_MEMBER_SEL~SUM]}),[*SORTED_ROW_AXIS]) ON ROWS
      FROM [Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Product].[Drink], [Gender].[*TOTAL_MEMBER_SEL~SUM]}
      {[Product].[Non-Consumable], [Gender].[*TOTAL_MEMBER_SEL~SUM]}
      {[Product].[Drink].[*DISPLAY_MEMBER], [Gender].[F]}
      {[Product].[Drink].[*DISPLAY_MEMBER], [Gender].[M]}
      {[Product].[Non-Consumable].[*DISPLAY_MEMBER], [Gender].[F]}
      {[Product].[Non-Consumable].[*DISPLAY_MEMBER], [Gender].[M]}
      Row #0: 7,582
      Row #1: 5,109
      Row #2: 3,690
      Row #3: 3,892
      Row #4: 2,607
      Row #5: 2,502
    RESULT
  end

  # Java: CachedExistsTest#testTop10Customers
  it "top 10 customers" do
    mdx = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Customers_],NONEMPTYCROSSJOIN([*BASE_MEMBERS__Product_],[*BASE_MEMBERS__Store_]))'
      SET [*METRIC_CJ_SET] AS 'FILTER([*NATIVE_CJ_SET],[Measures].[*TOP_Unit Sales_SEL~SUM] <= 10)'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Customers].CURRENTMEMBER.ORDERKEY,BASC,ANCESTOR([Customers].CURRENTMEMBER,[Customers].[City]).ORDERKEY,BASC,[Product].CURRENTMEMBER.ORDERKEY,BASC,[Measures].[*SORTED_MEASURE],BDESC)'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
      SET [*BASE_MEMBERS__Store_] AS '[Store].[Store Country].MEMBERS'
      SET [*BASE_MEMBERS__Customers_] AS '[Customers].[Name].MEMBERS'
      SET [*TOP_SET] AS 'ORDER(GENERATE([*NATIVE_CJ_SET],{[Customers].CURRENTMEMBER}),([Measures].[Unit Sales],[Education Level].[*TOPBOTTOM_CTX_SET_SUM]),BDESC)'
      SET [*BASE_MEMBERS__Product_] AS '{[Product].[All Products].[Drink],[Product].[All Products].[Food]}'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*METRIC_CJ_SET], {([Customers].CURRENTMEMBER,[Product].CURRENTMEMBER,[Store].CURRENTMEMBER)})'
      MEMBER [Education Level].[*TOPBOTTOM_CTX_SET_SUM] AS 'SUM(CachedExists([*NATIVE_CJ_SET],([Customers].CURRENTMEMBER), "*NATIVE_CJ_SET"))', SOLVE_ORDER=100
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
      MEMBER [Measures].[*SORTED_MEASURE] AS '([Measures].[*FORMATTED_MEASURE_0])', SOLVE_ORDER=400
      MEMBER [Measures].[*TOP_Unit Sales_SEL~SUM] AS 'RANK([Customers].CURRENTMEMBER,[*TOP_SET])', SOLVE_ORDER=400
      SELECT
      [*BASE_MEMBERS__Measures_] ON COLUMNS
      , NON EMPTY
      [*SORTED_ROW_AXIS] ON ROWS
      FROM [Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Customers].[USA].[WA].[Spokane].[Joann Mramor], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Joann Mramor], [Product].[Food], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Jack Zucconi], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Jack Zucconi], [Product].[Food], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Mary Francis Benigar], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Mary Francis Benigar], [Product].[Food], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Kristin Miller], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Kristin Miller], [Product].[Food], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[James Horvat], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[James Horvat], [Product].[Food], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Frank Darrell], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Frank Darrell], [Product].[Food], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Ida Rodriguez], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Ida Rodriguez], [Product].[Food], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Matt Bellah], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Matt Bellah], [Product].[Food], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Emily Barela], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Emily Barela], [Product].[Food], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Wildon Cameron], [Product].[Drink], [Store].[USA]}
      {[Customers].[USA].[WA].[Spokane].[Wildon Cameron], [Product].[Food], [Store].[USA]}
      Row #0: 57
      Row #1: 267
      Row #2: 26
      Row #3: 279
      Row #4: 37
      Row #5: 390
      Row #6: 16
      Row #7: 294
      Row #8: 40
      Row #9: 344
      Row #10: 49
      Row #11: 252
      Row #12: 38
      Row #13: 319
      Row #14: 36
      Row #15: 273
      Row #16: 26
      Row #17: 291
      Row #18: 47
      Row #19: 319
    RESULT
  end

  # Java: CachedExistsTest#testTop1CustomersWithColumnLevel
  it "top 1 customers with column level" do
    mdx = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Time_],NONEMPTYCROSSJOIN([*BASE_MEMBERS__Product_],NONEMPTYCROSSJOIN([*BASE_MEMBERS__Education Level_],[*BASE_MEMBERS__Customers_])))'
      SET [*METRIC_CJ_SET] AS 'FILTER([*NATIVE_CJ_SET],[Measures].[*TOP_Unit Sales_SEL~SUM] <= 1)'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Product].CURRENTMEMBER.ORDERKEY,BASC,[Education Level].CURRENTMEMBER.ORDERKEY,BASC,[Measures].[*SORTED_MEASURE],BDESC)'
      SET [*NATIVE_MEMBERS__Time_] AS 'GENERATE([*NATIVE_CJ_SET], {[Time].CURRENTMEMBER})'
      SET [*SORTED_COL_AXIS] AS 'ORDER([*CJ_COL_AXIS],[Time].CURRENTMEMBER.ORDERKEY,BASC,[Measures].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*BASE_MEMBERS__Education Level_] AS '{[Education Level].[All Education Levels].[Bachelors Degree]}'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
      SET [*BASE_MEMBERS__Customers_] AS '[Customers].[Name].MEMBERS'
      SET [*CJ_COL_AXIS] AS 'GENERATE([*METRIC_CJ_SET], {([Time].CURRENTMEMBER)})'
      SET [*BASE_MEMBERS__Product_] AS '{[Product].[All Products].[Drink]}'
      SET [*BASE_MEMBERS__Time_] AS '[Time].[Year].MEMBERS'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*METRIC_CJ_SET], {([Product].CURRENTMEMBER,[Education Level].CURRENTMEMBER,[Customers].CURRENTMEMBER)})'
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
      MEMBER [Measures].[*SORTED_MEASURE] AS '([Measures].[*FORMATTED_MEASURE_0],[Time].[*CTX_MEMBER_SEL~SUM])', SOLVE_ORDER=400
      MEMBER [Measures].[*TOP_Unit Sales_SEL~SUM] AS 'RANK([Customers].CURRENTMEMBER,ORDER(GENERATE(CACHEDEXISTS([*NATIVE_CJ_SET],([Product].CURRENTMEMBER, [Education Level].CURRENTMEMBER),"[*NATIVE_CJ_SET]"),{[Customers].CURRENTMEMBER}),([Measures].[Unit Sales],[Product].CURRENTMEMBER,[Education Level].CURRENTMEMBER,[Time].[*CTX_MEMBER_SEL~SUM]),BDESC))', SOLVE_ORDER=400
      MEMBER [Time].[*CTX_MEMBER_SEL~SUM] AS 'SUM([*NATIVE_MEMBERS__Time_])', SOLVE_ORDER=97
      SELECT
      CROSSJOIN([*SORTED_COL_AXIS],[*BASE_MEMBERS__Measures_]) ON COLUMNS
      , NON EMPTY
      [*SORTED_ROW_AXIS] ON ROWS
      FROM [Sales]
    MDX
    assert_query_returns @olap, mdx, <<~RESULT
      Axis #0:
      {}
      Axis #1:
      {[Time].[1997], [Measures].[*FORMATTED_MEASURE_0]}
      Axis #2:
      {[Product].[Drink], [Education Level].[Bachelors Degree], [Customers].[USA].[WA].[Spokane].[Wildon Cameron]}
      Row #0: 47
    RESULT
  end

  # Java: CachedExistsTest#testMondrian2704
  describe "Mondrian-2704" do
    ALTERNATE_SALES_CUBE = <<~XML
      <Cube name="Alternate Sales">
        <Table name="sales_fact_1997"/>
        <Dimension name="Time" type="TimeDimension" foreignKey="time_id">
          <Hierarchy name="Time" hasAll="true" primaryKey="time_id">
            <Table name="time_by_day"/>
            <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true" levelType="TimeYears"/>
          </Hierarchy>
          <Hierarchy hasAll="true" name="Weekly" primaryKey="time_id">
            <Table name="time_by_day"/>
            <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true" levelType="TimeYears"/>
          </Hierarchy>
          <Hierarchy hasAll="true" name="Weekly2" primaryKey="time_id">
            <Table name="time_by_day"/>
            <Level name="Year" column="the_year" type="Numeric" uniqueMembers="true" levelType="TimeYears"/>
          </Hierarchy>
        </Dimension>
        <Measure name="Unit Sales" column="unit_sales" aggregator="sum" formatString="Standard"/>
      </Cube>
    XML

    before(:all) do
      # New cubes must appear before <VirtualCube> in the schema — Mondrian's
      # parser silently ignores <Cube> elements that appear after <Role>.
      schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{ALTERNATE_SALES_CUBE}<VirtualCube")
      params = CONNECTION_PARAMS.merge(catalog_content: schema)
      params.delete(:catalog)
      @alternate_olap = Mondrian::OLAP::Connection.create(params)
    end

    after(:all) do
      @alternate_olap&.close
    end

    # Verifies second arg of CachedExists uses a tuple type
    it "CachedExists with tuple type second argument" do
      mdx = <<~MDX
        WITH
        SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Time_],[*BASE_MEMBERS__Time.Weekly_])'
        SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Time].CURRENTMEMBER.ORDERKEY,BASC,[Time.Weekly].CURRENTMEMBER.ORDERKEY,BASC)'
        SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
        SET [*BASE_MEMBERS__Time.Weekly_] AS '[Time.Weekly].[Year].MEMBERS'
        SET [*BASE_MEMBERS__Time_] AS '[Time].[Year].MEMBERS'
        SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Time].CURRENTMEMBER,[Time.Weekly].CURRENTMEMBER)})'
        MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
        MEMBER [Time.Weekly].[*DEFAULT_MEMBER] AS '[Time.Weekly].DEFAULTMEMBER', SOLVE_ORDER=-400
        MEMBER [Time.Weekly].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CACHEDEXISTS([*CJ_ROW_AXIS],([Time].CURRENTMEMBER),"[*CJ_ROW_AXIS]"))', SOLVE_ORDER=99
        MEMBER [Time].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM([*CJ_ROW_AXIS])', SOLVE_ORDER=100
        SELECT
        [*BASE_MEMBERS__Measures_] ON COLUMNS
        , NON EMPTY
        UNION(CROSSJOIN({[Time].[*TOTAL_MEMBER_SEL~SUM]},{([Time.Weekly].[*DEFAULT_MEMBER])}),UNION(CROSSJOIN(GENERATE([*CJ_ROW_AXIS], {([Time].CURRENTMEMBER)}),{[Time.Weekly].[*TOTAL_MEMBER_SEL~SUM]}),[*SORTED_ROW_AXIS])) ON ROWS
        FROM [Alternate Sales]
      MDX
      assert_query_returns @alternate_olap, mdx, <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[*FORMATTED_MEASURE_0]}
        Axis #2:
        {[Time].[*TOTAL_MEMBER_SEL~SUM], [Time.Weekly].[*DEFAULT_MEMBER]}
        {[Time].[1997], [Time.Weekly].[*TOTAL_MEMBER_SEL~SUM]}
        {[Time].[1997], [Time.Weekly].[1997]}
        Row #0: 266,773
        Row #1: 266,773
        Row #2: 266,773
      RESULT
    end

    # Verifies second arg of CachedExists uses a member type
    it "CachedExists with member type second argument" do
      mdx = <<~MDX
        WITH
        SET [*NATIVE_CJ_SET] AS 'NONEMPTYCROSSJOIN([*BASE_MEMBERS__Time.Weekly_],NONEMPTYCROSSJOIN([*BASE_MEMBERS__Time_],[*BASE_MEMBERS__Time.Weekly2_]))'
        SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Time.Weekly].CURRENTMEMBER.ORDERKEY,BASC,[Time].CURRENTMEMBER.ORDERKEY,BASC,[Time.Weekly2].CURRENTMEMBER.ORDERKEY,BASC)'
        SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
        SET [*BASE_MEMBERS__Time.Weekly2_] AS '[Time.Weekly2].[Year].MEMBERS'
        SET [*BASE_MEMBERS__Time.Weekly_] AS '[Time.Weekly].[Year].MEMBERS'
        SET [*BASE_MEMBERS__Time_] AS '[Time].[Year].MEMBERS'
        SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Time.Weekly].CURRENTMEMBER,[Time].CURRENTMEMBER,[Time.Weekly2].CURRENTMEMBER)})'
        MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
        MEMBER [Time.Weekly2].[*TOTAL_MEMBER_SEL~SUM] AS 'SUM(CACHEDEXISTS([*CJ_ROW_AXIS],([Time.Weekly].CURRENTMEMBER, [Time].CURRENTMEMBER),"[*CJ_ROW_AXIS]"))', SOLVE_ORDER=98
        SELECT
        [*BASE_MEMBERS__Measures_] ON COLUMNS
        , NON EMPTY
        UNION(CROSSJOIN(GENERATE([*CJ_ROW_AXIS], {([Time.Weekly].CURRENTMEMBER,[Time].CURRENTMEMBER)}),{[Time.Weekly2].[*TOTAL_MEMBER_SEL~SUM]}),[*SORTED_ROW_AXIS]) ON ROWS
        FROM [Alternate Sales]
      MDX
      assert_query_returns @alternate_olap, mdx, <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[*FORMATTED_MEASURE_0]}
        Axis #2:
        {[Time.Weekly].[1997], [Time].[1997], [Time.Weekly2].[*TOTAL_MEMBER_SEL~SUM]}
        {[Time.Weekly].[1997], [Time].[1997], [Time.Weekly2].[1997]}
        Row #0: 266,773
        Row #1: 266,773
      RESULT
    end
  end
end
