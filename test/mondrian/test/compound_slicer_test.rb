# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/test/CompoundSlicerTest.java
describe "CompoundSlicerTest" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Walk the Java exception cause chain to build a full error message.
  def full_error_message(exception)
    messages = []
    cause = exception
    while cause
      messages << cause.message if cause.message
      cause = cause.respond_to?(:cause) ? cause.cause : nil
      break if cause && messages.include?(cause.message)
    end
    messages.join(" ")
  end

  # Checks whether query produces the same results with the native.* props
  # enabled as it does with the props disabled.
  # Matches Java BatchTestCase.verifySameNativeAndNot.
  def verify_same_native_and_not(mdx, olap = @olap)
    with_properties(
      EnableNativeCrossJoin: true,
      EnableNativeFilter: true,
      EnableNativeNonEmpty: true,
      EnableNativeTopCount: true
    ) do
      result_native = format_result(olap.execute(mdx))

      with_properties(
        EnableNativeCrossJoin: false,
        EnableNativeFilter: false,
        EnableNativeNonEmpty: false,
        EnableNativeTopCount: false
      ) do
        result_non_native = format_result(olap.execute(mdx))
        assert_equal result_native, result_non_native
      end
    end
  end

  # Creates a connection with "Warehouse and Sales" virtual cube modified
  # to include Customer Count measure and a calculated member.
  # Mirrors Java CompoundSlicerTest.virtualCubeWithDC().
  def virtual_cube_with_dc
    schema = SchemaHelper::FOODMART_SCHEMA.dup

    # Change the defaultMeasure to "Warehouse Sales"
    schema = schema.sub(
      '<VirtualCube name="Warehouse and Sales" defaultMeasure="Store Sales">',
      '<VirtualCube name="Warehouse and Sales" defaultMeasure="Warehouse Sales">'
    )

    # Add VirtualCubeMeasure for Customer Count before the first CalculatedMember
    # in the Warehouse and Sales virtual cube
    virtual_cube_measure = '<VirtualCubeMeasure cubeName="Sales" name="[Measures].[Customer Count]"/>'
    calculated_member = <<~XML.chomp
      <CalculatedMember name="Unit Sales by Customer" dimension="Measures">
        <Formula>Measures.[Unit Sales]/Measures.[Customer Count]</Formula>
      </CalculatedMember>
    XML

    # Find the Warehouse and Sales virtual cube and insert within it
    cube_start = schema.index('<VirtualCube name="Warehouse and Sales"')
    cube_end = schema.index("</VirtualCube>", cube_start)

    # Insert calculated member before closing tag
    schema = schema[0...cube_end] + calculated_member + "\n" + schema[cube_end..]
    cube_end += calculated_member.length + 1

    # Insert the VirtualCubeMeasure before the first CalculatedMember in this cube
    calc_member_pos = schema.index("<CalculatedMember", cube_start)
    if calc_member_pos && calc_member_pos < cube_end
      schema = schema[0...calc_member_pos] + virtual_cube_measure + "\n" + schema[calc_member_pos..]
    end

    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  # Java: CompoundSlicerTest#testSimulatedCompoundSlicer
  it "simulated compound slicer using calculated member and set in WHERE" do
    # Query that simulates a compound slicer by creating a calculated member
    # that aggregates over a set and places it in the WHERE clause.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with
        member [Measures].[Price per Unit] as
          [Measures].[Store Sales] / [Measures].[Unit Sales]
        set [Top Products] as
          TopCount(
            [Product].[Brand Name].Members,
            3,
            ([Measures].[Unit Sales], [Time].[1997].[Q3]))
        member [Product].[Top] as
          Aggregate([Top Products])
      select {
        [Measures].[Unit Sales],
        [Measures].[Price per Unit]} on 0,
       [Gender].Children * [Marital Status].Children on 1
      from [Sales]
      where ([Product].[Top], [Time].[1997].[Q3])
    MDX
      Axis #0:
      {[Product].[Top], [Time].[1997].[Q3]}
      Axis #1:
      {[Measures].[Unit Sales]}
      {[Measures].[Price per Unit]}
      Axis #2:
      {[Gender].[F], [Marital Status].[M]}
      {[Gender].[F], [Marital Status].[S]}
      {[Gender].[M], [Marital Status].[M]}
      {[Gender].[M], [Marital Status].[S]}
      Row #0: 779
      Row #0: 2.40
      Row #1: 811
      Row #1: 2.24
      Row #2: 829
      Row #2: 2.23
      Row #3: 886
      Row #3: 2.25
    RESULT

    # Now the equivalent query, using a set in the slicer.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with
        member [Measures].[Price per Unit] as
          [Measures].[Store Sales] / [Measures].[Unit Sales]
        set [Top Products] as
          TopCount(
            [Product].[Brand Name].Members,
            3,
            ([Measures].[Unit Sales], [Time].[1997].[Q3]))
      select {
        [Measures].[Unit Sales],
        [Measures].[Price per Unit]} on 0,
       [Gender].Children * [Marital Status].Children on 1
      from [Sales]
      where [Top Products] * [Time].[1997].[Q3]
    MDX
      Axis #0:
      {[Product].[Food].[Produce].[Vegetables].[Fresh Vegetables].[Hermanos], [Time].[1997].[Q3]}
      {[Product].[Food].[Produce].[Vegetables].[Fresh Vegetables].[Tell Tale], [Time].[1997].[Q3]}
      {[Product].[Food].[Produce].[Vegetables].[Fresh Vegetables].[Ebony], [Time].[1997].[Q3]}
      Axis #1:
      {[Measures].[Unit Sales]}
      {[Measures].[Price per Unit]}
      Axis #2:
      {[Gender].[F], [Marital Status].[M]}
      {[Gender].[F], [Marital Status].[S]}
      {[Gender].[M], [Marital Status].[M]}
      {[Gender].[M], [Marital Status].[S]}
      Row #0: 779
      Row #0: 2.40
      Row #1: 811
      Row #1: 2.24
      Row #2: 829
      Row #2: 2.23
      Row #3: 886
      Row #3: 2.25
    RESULT
  end

  # Java: CompoundSlicerTest#testCompoundSlicerExcept
  # Test case for Bug MONDRIAN-637, "Using Except in the slicer makes no sense"
  it "compound slicer with EXCEPT" do
    expected = <<~RESULT
      Axis #0:
      {[Promotion Media].[Bulk Mail]}
      {[Promotion Media].[Cash Register Handout]}
      {[Promotion Media].[Daily Paper, Radio]}
      {[Promotion Media].[Daily Paper, Radio, TV]}
      {[Promotion Media].[In-Store Coupon]}
      {[Promotion Media].[No Media]}
      {[Promotion Media].[Product Attachment]}
      {[Promotion Media].[Radio]}
      {[Promotion Media].[Street Handout]}
      {[Promotion Media].[Sunday Paper]}
      {[Promotion Media].[Sunday Paper, Radio]}
      {[Promotion Media].[Sunday Paper, Radio, TV]}
      {[Promotion Media].[TV]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 259,035
      Row #1: 127,871
      Row #2: 131,164
    RESULT

    # slicer expression that inherits [Promotion Media] member from context
    assert_query_returns @olap, <<~MDX, expected
      select [Measures].[Unit Sales] on 0,
       [Gender].Members on 1
      from [Sales]
      where Except(
        [Promotion Media].Children,
        {[Promotion Media].[Daily Paper]})
    MDX

    # similar query, but don't assume that [Promotion Media].CurrentMember
    # = [Promotion Media].[All Media]
    assert_query_returns @olap, <<~MDX, expected
      select [Measures].[Unit Sales] on 0,
       [Gender].Members on 1
      from [Sales]
      where Except(
        [Promotion Media].[All Media].Children,
        {[Promotion Media].[Daily Paper]})
    MDX

    # reference query, computing the same numbers a different way
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with member [Promotion Media].[Except Daily Paper] as
        Aggregate(
          Except(
            [Promotion Media].Children,
            {[Promotion Media].[Daily Paper]}))
      select [Measures].[Unit Sales]
       * {[Promotion Media],
          [Promotion Media].[Daily Paper],
          [Promotion Media].[Except Daily Paper]} on 0,
       [Gender].Members on 1
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Unit Sales], [Promotion Media].[All Media]}
      {[Measures].[Unit Sales], [Promotion Media].[Daily Paper]}
      {[Measures].[Unit Sales], [Promotion Media].[Except Daily Paper]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 266,773
      Row #0: 7,738
      Row #0: 259,035
      Row #1: 131,558
      Row #1: 3,687
      Row #1: 127,871
      Row #2: 135,215
      Row #2: 4,051
      Row #2: 131,164
    RESULT
  end

  # Java: CompoundSlicerTest#testCompoundSlicerWithCellFormatter
  it "compound slicer with cell formatter" do
    # The Java test uses mondrian.test.UdfTest$FooBarCellFormatter which is a
    # test-only class not available in the runtime JAR. Use an equivalent
    # JavaScript-based CellFormatter via the <CellFormatter> element.
    olap = connection_with_modified_cube("Sales",
      measures: <<~XML
        <Measure name='Unit Sales Foo Bar' column='unit_sales'
            aggregator='sum' formatString='Standard'>
          <CellFormatter>
            <Script language="JavaScript">return "foo" + value + "bar";</Script>
          </CellFormatter>
        </Measure>
      XML
    )
    begin
      # the cell formatter for the measure should still be used
      assert_query_returns olap, <<~MDX, <<~RESULT
        select from sales where
         measures.[Unit Sales Foo Bar] * Gender.Gender.members
      MDX
        Axis #0:
        {[Measures].[Unit Sales Foo Bar], [Gender].[F]}
        {[Measures].[Unit Sales Foo Bar], [Gender].[M]}
        foo266773bar
      RESULT

      assert_query_returns olap, <<~MDX, <<~RESULT
        select from sales where
         Gender.Gender.members * measures.[Unit Sales Foo Bar]
      MDX
        Axis #0:
        {[Gender].[F], [Measures].[Unit Sales Foo Bar]}
        {[Gender].[M], [Measures].[Unit Sales Foo Bar]}
        foo266773bar
      RESULT
    ensure
      olap.close
    end
  end

  # Java: CompoundSlicerTest#testMondrian1226
  it "MONDRIAN-1226 compound slicer with range and TopCount" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with set a as '([Time].[1997].[Q1] : [Time].[1997].[Q2])'
      member Time.x as Aggregate(a,[Measures].[Store Sales])
      member Measures.x1 as ([Time].[1997].[Q1],[Measures].[Store Sales])
      member Measures.x2 as ([Time].[1997].[Q2], [Measures].[Store Sales])
      set products as TopCount(Product.[Product Name].Members,1,Measures.[Store Sales])
      SELECT
      NON EMPTY products ON 1,
      NON EMPTY {[Measures].[Store Sales], Measures.x1, Measures.x2} ON 0
      FROM [Sales]
      where ([Time].[1997].[Q1] : [Time].[1997].[Q2])
    MDX
      Axis #0:
      {[Time].[1997].[Q1]}
      {[Time].[1997].[Q2]}
      Axis #1:
      {[Measures].[Store Sales]}
      {[Measures].[x1]}
      {[Measures].[x2]}
      Axis #2:
      {[Product].[Food].[Eggs].[Eggs].[Eggs].[Urban].[Urban Small Eggs]}
      Row #0: 497.42
      Row #0: 235.62
      Row #0: 261.80
    RESULT
  end

  # Java: CompoundSlicerTest#testCompoundSlicerOverTuples
  it "compound slicer over tuples" do
    # reference query
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
          TopCount(
            [Product].[Product Category].Members
            * [Customers].[City].Members,
            10) on 1
      from [Sales]
      where [Time].[1997].[Q3]
    MDX
      Axis #0:
      {[Time].[1997].[Q3]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[Burnaby]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[Cliffside]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[Haney]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[Ladner]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[Langford]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[Langley]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[Metchosin]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[N. Vancouver]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[Newton]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine], [Customers].[Canada].[BC].[Oak Bay]}
      Row #0: #{" "}
      Row #1: #{" "}
      Row #2: #{" "}
      Row #3: #{" "}
      Row #4: #{" "}
      Row #5: #{" "}
      Row #6: #{" "}
      Row #7: #{" "}
      Row #8: #{" "}
      Row #9: #{" "}
    RESULT

    # The actual query. Note that the set in the slicer has two dimensions.
    # This could not be expressed using calculated members and the
    # Aggregate function.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with
        member [Measures].[Price per Unit] as
          [Measures].[Store Sales] / [Measures].[Unit Sales]
        set [Top Product Cities] as
          TopCount(
            [Product].[Product Category].Members
            * [Customers].[City].Members,
            3,
            ([Measures].[Unit Sales], [Time].[1997].[Q3]))
      select {
        [Measures].[Unit Sales],
        [Measures].[Price per Unit]} on 0,
       [Gender].Children * [Marital Status].Children on 1
      from [Sales]
      where [Top Product Cities] * [Time].[1997].[Q3]
    MDX
      Axis #0:
      {[Product].[Food].[Snack Foods].[Snack Foods], [Customers].[USA].[WA].[Spokane], [Time].[1997].[Q3]}
      {[Product].[Food].[Produce].[Vegetables], [Customers].[USA].[WA].[Spokane], [Time].[1997].[Q3]}
      {[Product].[Food].[Snack Foods].[Snack Foods], [Customers].[USA].[WA].[Puyallup], [Time].[1997].[Q3]}
      Axis #1:
      {[Measures].[Unit Sales]}
      {[Measures].[Price per Unit]}
      Axis #2:
      {[Gender].[F], [Marital Status].[M]}
      {[Gender].[F], [Marital Status].[S]}
      {[Gender].[M], [Marital Status].[M]}
      {[Gender].[M], [Marital Status].[S]}
      Row #0: 483
      Row #0: 2.21
      Row #1: 419
      Row #1: 2.21
      Row #2: 422
      Row #2: 2.22
      Row #3: 332
      Row #3: 2.20
    RESULT
  end

  # Java: CompoundSlicerTest#testEmptySetSlicerReturnsNull
  it "empty set slicer returns null" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Product].Children on 1
      from [Sales]
      where {}
    MDX
      Axis #0:
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Drink]}
      {[Product].[Food]}
      {[Product].[Non-Consumable]}
      Row #0: #{" "}
      Row #1: #{" "}
      Row #2: #{" "}
    RESULT
  end

  # Java: CompoundSlicerTest#testEmptySetSlicerViaExpressionReturnsNull
  it "empty set slicer via expression returns null" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Product].Children on 1
      from [Sales]
      where filter([Gender].members * [Marital Status].members, 1 = 0)
    MDX
      Axis #0:
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Product].[Drink]}
      {[Product].[Food]}
      {[Product].[Non-Consumable]}
      Row #0: #{" "}
      Row #1: #{" "}
      Row #2: #{" "}
    RESULT
  end

  # Java: CompoundSlicerTest#testCompoundSlicer
  it "compound slicer with multiple members" do
    # Reference query.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where {[Product].[Drink]}
    MDX
      Axis #0:
      {[Product].[Drink]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 24,597
      Row #1: 12,202
      Row #2: 12,395
    RESULT

    # Reference query.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where {[Product].[Food]}
    MDX
      Axis #0:
      {[Product].[Food]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 191,940
      Row #1: 94,814
      Row #2: 97,126
    RESULT

    # Sum members at same level.
    # Note that 216,537 = 24,597 (drink) + 191,940 (food).
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where {[Product].[Drink], [Product].[Food]}
    MDX
      Axis #0:
      {[Product].[Drink]}
      {[Product].[Food]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 216,537
      Row #1: 107,016
      Row #2: 109,521
    RESULT

    # sum list that contains duplicates
    # duplicates are ignored (checked SSAS 2005)
    # Bug.BugMondrian555Fixed is false, so using the non-fixed expected result
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where {[Product].[Drink], [Product].[Food], [Product].[Drink]}
    MDX
      Axis #0:
      {[Product].[Drink]}
      {[Product].[Food]}
      {[Product].[Drink]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 241,134
      Row #1: 119,218
      Row #2: 121,916
    RESULT

    # sum list that contains a null member -
    # null member is ignored;
    # confirmed behavior with ssas 2005
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where {[Product].[All Products].Parent, [Product].[Food], [Product].[Drink]}
    MDX
      Axis #0:
      {[Product].[Food]}
      {[Product].[Drink]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 216,537
      Row #1: 107,016
      Row #2: 109,521
    RESULT

    # Reference query.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where {
        [Product].[Drink],
        [Product].[Food].[Dairy]}
    MDX
      Axis #0:
      {[Product].[Drink]}
      {[Product].[Food].[Dairy]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 37,482
      Row #1: 18,715
      Row #2: 18,767
    RESULT

    # Sum list that contains a member and one of its children;
    # SSAS 2005 doesn't simply sum them: it behaves behavior as if
    # predicates are pushed down to the fact table. Mondrian double-counts,
    # and that is a bug.
    # Bug.BugMondrian555Fixed is false, so using the non-fixed expected result
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where {
        [Product].[Drink],
        [Product].[Food].[Dairy],
        [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer]}
    MDX
      Axis #0:
      {[Product].[Drink]}
      {[Product].[Food].[Dairy]}
      {[Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 39,165
      Row #1: 19,532
      Row #2: 19,633
    RESULT

    # The correct behavior of the aggregate function is to double-count.
    # SSAS 2005 and Mondrian give the same behavior.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with member [Product].[Foo] as
        Aggregate({
          [Product].[Drink],
          [Product].[Food].[Dairy],
          [Product].[Drink].[Alcoholic Beverages].[Beer and Wine].[Beer]})
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where [Product].[Foo]
    MDX
      Axis #0:
      {[Product].[Foo]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 39,165
      Row #1: 19,532
      Row #2: 19,633
    RESULT
  end

  # Java: CompoundSlicerTest#testSlicerContainsNullMember
  # Slicer that is a member expression that evaluates to null.
  # SSAS 2005 allows this, and returns null cells.
  it "slicer contains null member" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where [Product].Parent
    MDX
      Axis #0:
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: #{" "}
      Row #1: #{" "}
      Row #2: #{" "}
    RESULT
  end

  # Java: CompoundSlicerTest#testSlicerContainsLiteralNull
  # Slicer that is literal null.
  # Bug.Ssas2005Compatible is false, so Mondrian gives an error.
  it "slicer contains literal null raises error" do
    mdx = <<~MDX
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where null
    MDX
    error = assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
    full_message = full_error_message(error)
    assert full_message.include?("Function does not support NULL member parameter"),
      "Expected error containing 'Function does not support NULL member parameter', got: #{full_message}"
  end

  # Java: CompoundSlicerTest#testSlicerContainsPartiallyNullMember
  # Slicer that is a tuple and one of the members evaluates to null;
  # that makes it a null tuple, and it is eliminated from the list.
  it "slicer contains partially null member" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Unit Sales] on 0,
      [Gender].Members on 1
      from [Sales]
      where ([Product].Parent, [Store].[USA].[CA])
    MDX
      Axis #0:
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: #{" "}
      Row #1: #{" "}
      Row #2: #{" "}
    RESULT
  end

  # Java: CompoundSlicerTest#testCompoundSlicerWithDistinctCount
  it "compound slicer with distinct count" do
    # Reference query.
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Customer Count] on 0,
        {[Store].[USA].[CA], [Store].[USA].[OR].[Portland]}
        * {([Product].[Food], [Time].[1997].[Q1]),
          ([Product].[Drink], [Time].[1997].[Q2].[4])} on 1
      from [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Customer Count]}
      Axis #2:
      {[Store].[USA].[CA], [Product].[Food], [Time].[1997].[Q1]}
      {[Store].[USA].[CA], [Product].[Drink], [Time].[1997].[Q2].[4]}
      {[Store].[USA].[OR].[Portland], [Product].[Food], [Time].[1997].[Q1]}
      {[Store].[USA].[OR].[Portland], [Product].[Drink], [Time].[1997].[Q2].[4]}
      Row #0: 1,069
      Row #1: 155
      Row #2: 332
      Row #3: 48
    RESULT

    # The figures look reasonable, because:
    #  332 + 48 = 380 > 352
    #  1069 + 155 = 1224 > 1175
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select [Measures].[Customer Count] on 0,
      {[Store].[USA].[CA], [Store].[USA].[OR].[Portland]} on 1
      from [Sales]
      where {
        ([Product].[Food], [Time].[1997].[Q1]),
        ([Product].[Drink], [Time].[1997].[Q2].[4])}
    MDX
      Axis #0:
      {[Product].[Food], [Time].[1997].[Q1]}
      {[Product].[Drink], [Time].[1997].[Q2].[4]}
      Axis #1:
      {[Measures].[Customer Count]}
      Axis #2:
      {[Store].[USA].[CA]}
      {[Store].[USA].[OR].[Portland]}
      Row #0: 1,175
      Row #1: 352
    RESULT
  end

  # Java: CompoundSlicerTest#testRollupAvg
  # Test case for Bug MONDRIAN-675,
  # "Allow rollup of measures based on AVG aggregate function"
  it "rollup with AVG aggregate function" do
    olap = connection_with_modified_cube("Sales",
      measures: <<~XML
        <Measure name='Avg Unit Sales' aggregator='avg' column='unit_sales'/>
        <Measure name='Count Unit Sales' aggregator='count' column='unit_sales'/>
        <Measure name='Sum Unit Sales' aggregator='sum' column='unit_sales'/>
      XML
    )
    begin
      # basic query with avg
      assert_query_returns olap, <<~MDX, <<~RESULT
        select from [Sales]
        where [Measures].[Avg Unit Sales]
      MDX
        Axis #0:
        {[Measures].[Avg Unit Sales]}
        3.072
      RESULT

      # roll up using compound slicer
      # (should give a real value, not an error)
      assert_query_returns olap, <<~MDX, <<~RESULT
        select from [Sales]
        where [Measures].[Avg Unit Sales]
           * {[Customers].[USA].[OR], [Customers].[USA].[CA]}
      MDX
        Axis #0:
        {[Measures].[Avg Unit Sales], [Customers].[USA].[OR]}
        {[Measures].[Avg Unit Sales], [Customers].[USA].[CA]}
        3.092
      RESULT

      # roll up using a named set
      assert_query_returns olap, <<~MDX, <<~RESULT
        with member [Customers].[OR and CA] as Aggregate(
         {[Customers].[USA].[OR], [Customers].[USA].[CA]})
        select from [Sales]
        where ([Measures].[Avg Unit Sales], [Customers].[OR and CA])
      MDX
        Axis #0:
        {[Measures].[Avg Unit Sales], [Customers].[OR and CA]}
        3.092
      RESULT
    ensure
      olap.close
    end
  end

  # Java: CompoundSlicerTest#testBugMondrian899
  # Test case for Bug MONDRIAN-899,
  # "Order() function does not work properly together with WHERE clause"
  it "MONDRIAN-899 Order with compound slicer" do
    expected = <<~RESULT
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      {[Time].[1997].[Q1].[3]}
      {[Time].[1997].[Q2].[4]}
      {[Time].[1997].[Q2].[5]}
      {[Time].[1997].[Q2].[6]}
      {[Time].[1997].[Q3].[7]}
      {[Time].[1997].[Q3].[8]}
      {[Time].[1997].[Q3].[9]}
      {[Time].[1997].[Q4].[10]}
      {[Time].[1997].[Q4].[11]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Customers].[USA].[WA].[Spokane].[Wildon Cameron]}
      {[Customers].[USA].[WA].[Spokane].[Emily Barela]}
      {[Customers].[USA].[WA].[Spokane].[Dauna Barton]}
      {[Customers].[USA].[WA].[Spokane].[Mona Vigil]}
      {[Customers].[USA].[WA].[Spokane].[Linda Combs]}
      {[Customers].[USA].[WA].[Spokane].[Eric Winters]}
      {[Customers].[USA].[WA].[Spokane].[Jack Zucconi]}
      {[Customers].[USA].[WA].[Spokane].[Luann Crawford]}
      {[Customers].[USA].[WA].[Spokane].[Suzanne Davis]}
      {[Customers].[USA].[WA].[Spokane].[Lucy Flowers]}
      {[Customers].[USA].[WA].[Spokane].[Donna Weisinger]}
      {[Customers].[USA].[WA].[Spokane].[Stanley Marks]}
      {[Customers].[USA].[WA].[Spokane].[James Short]}
      {[Customers].[USA].[WA].[Spokane].[Curtis Pollard]}
      {[Customers].[USA].[WA].[Spokane].[Dawn Laner]}
      {[Customers].[USA].[WA].[Spokane].[Patricia Towns]}
      {[Customers].[USA].[WA].[Puyallup].[William Wade]}
      {[Customers].[USA].[WA].[Spokane].[Lorriene Weathers]}
      {[Customers].[USA].[WA].[Spokane].[Grace McLaughlin]}
      {[Customers].[USA].[WA].[Spokane].[Edna Woodson]}
      {[Customers].[USA].[WA].[Spokane].[Harry Torphy]}
      {[Customers].[USA].[WA].[Spokane].[Anne Allard]}
      {[Customers].[USA].[WA].[Spokane].[Bonnie Staley]}
      {[Customers].[USA].[WA].[Olympia].[Patricia Gervasi]}
      {[Customers].[USA].[WA].[Spokane].[Shirley Gottbehuet]}
      {[Customers].[USA].[WA].[Puyallup].[Jeremy Styers]}
      {[Customers].[USA].[WA].[Spokane].[Beth Ohnheiser]}
      {[Customers].[USA].[WA].[Bremerton].[Harold Powers]}
      {[Customers].[USA].[WA].[Spokane].[Daniel Thompson]}
      {[Customers].[USA].[WA].[Spokane].[Fran McEvilly]}
      Row #0: 327
      Row #1: 323
      Row #2: 319
      Row #3: 308
      Row #4: 305
      Row #5: 296
      Row #6: 296
      Row #7: 295
      Row #8: 291
      Row #9: 289
      Row #10: 285
      Row #11: 284
      Row #12: 281
      Row #13: 279
      Row #14: 279
      Row #15: 278
      Row #16: 277
      Row #17: 271
      Row #18: 268
      Row #19: 266
      Row #20: 265
      Row #21: 264
      Row #22: 260
      Row #23: 251
      Row #24: 250
      Row #25: 249
      Row #26: 249
      Row #27: 248
      Row #28: 247
      Row #29: 247
    RESULT

    assert_query_returns @olap, <<~MDX, expected
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        Subset(Order([Customers].[Name].Members, [Measures].[Unit Sales], BDESC), 10.0, 30.0) ON ROWS
      from [Sales]
      where ([Time].[1997].[Q1].[2] : [Time].[1997].[Q4].[11])
    MDX

    # Equivalent query.
    assert_query_returns @olap, <<~MDX, expected
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        Tail(
          TopCount([Customers].[Name].Members, 40, [Measures].[Unit Sales]),
          30) ON ROWS
      from [Sales]
      where ([Time].[1997].[Q1].[2] : [Time].[1997].[Q4].[11])
    MDX
  end

  # Java: CompoundSlicerTest#testTopCount
  # similar to MONDRIAN-899 testcase
  it "TopCount with compound slicer range" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        TopCount([Customers].[USA].[WA].[Spokane].Children, 10, [Measures].[Unit Sales]) ON ROWS
      from [Sales]
      where ([Time].[1997].[Q1].[2] : [Time].[1997].[Q1].[3])
    MDX
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      {[Time].[1997].[Q1].[3]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Customers].[USA].[WA].[Spokane].[Grace McLaughlin]}
      {[Customers].[USA].[WA].[Spokane].[George Todero]}
      {[Customers].[USA].[WA].[Spokane].[Matt Bellah]}
      {[Customers].[USA].[WA].[Spokane].[Mary Francis Benigar]}
      {[Customers].[USA].[WA].[Spokane].[Lucy Flowers]}
      {[Customers].[USA].[WA].[Spokane].[David Hassard]}
      {[Customers].[USA].[WA].[Spokane].[Dauna Barton]}
      {[Customers].[USA].[WA].[Spokane].[Dora Sims]}
      {[Customers].[USA].[WA].[Spokane].[Joann Mramor]}
      {[Customers].[USA].[WA].[Spokane].[Mike Madrid]}
      Row #0: 131
      Row #1: 129
      Row #2: 113
      Row #3: 103
      Row #4: 95
      Row #5: 94
      Row #6: 92
      Row #7: 85
      Row #8: 79
      Row #9: 79
    RESULT
  end

  # Java: CompoundSlicerTest#testTopCountAllSlicers
  it "TopCount with all slicers crossjoined" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        TopCount([Customers].[USA].[WA].[Spokane].Children, 10, [Measures].[Unit Sales]) ON ROWS
      from [Sales]
      where {[Time].[1997].[Q1].[2] : [Time].[1997].[Q1].[3]}*{[Product].[All Products]}
    MDX
      Axis #0:
      {[Time].[1997].[Q1].[2], [Product].[All Products]}
      {[Time].[1997].[Q1].[3], [Product].[All Products]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Customers].[USA].[WA].[Spokane].[Grace McLaughlin]}
      {[Customers].[USA].[WA].[Spokane].[George Todero]}
      {[Customers].[USA].[WA].[Spokane].[Matt Bellah]}
      {[Customers].[USA].[WA].[Spokane].[Mary Francis Benigar]}
      {[Customers].[USA].[WA].[Spokane].[Lucy Flowers]}
      {[Customers].[USA].[WA].[Spokane].[David Hassard]}
      {[Customers].[USA].[WA].[Spokane].[Dauna Barton]}
      {[Customers].[USA].[WA].[Spokane].[Dora Sims]}
      {[Customers].[USA].[WA].[Spokane].[Joann Mramor]}
      {[Customers].[USA].[WA].[Spokane].[Mike Madrid]}
      Row #0: 131
      Row #1: 129
      Row #2: 113
      Row #3: 103
      Row #4: 95
      Row #5: 94
      Row #6: 92
      Row #7: 85
      Row #8: 79
      Row #9: 79
    RESULT
  end

  # Java: CompoundSlicerTest#testTopCountWithAggregatedMemberCMRange
  # Test case for the support of native top count with aggregated measures.
  # This version puts the range in a calculated member.
  it "TopCount with aggregated member using calculated member range" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with set TO_AGGREGATE as '([Time].[1997].[Q1] : [Time].[1997].[Q2])'
      member Time.x as Aggregate(TO_AGGREGATE, [Measures].[Store Sales])
      member Measures.x1 as ([Time].[1997].[Q1], [Measures].[Store Sales])
      member Measures.x2 as ([Time].[1997].[Q2], [Measures].[Store Sales])
       set products as TopCount(Product.[Product Name].Members, 2, Measures.[Store Sales])
       SELECT NON EMPTY products ON 1,
      NON EMPTY {[Measures].[Store Sales], Measures.x1, Measures.x2} ON 0
       FROM [Sales] where Time.x
    MDX
      Axis #0:
      {[Time].[x]}
      Axis #1:
      {[Measures].[Store Sales]}
      {[Measures].[x1]}
      {[Measures].[x2]}
      Axis #2:
      {[Product].[Food].[Eggs].[Eggs].[Eggs].[Urban].[Urban Small Eggs]}
      {[Product].[Food].[Snack Foods].[Snack Foods].[Dried Fruit].[Fort West].[Fort West Raspberry Fruit Roll]}
      Row #0: 497.42
      Row #0: 235.62
      Row #0: 261.80
      Row #1: 462.84
      Row #1: 226.20
      Row #1: 236.64
    RESULT
  end

  # Java: CompoundSlicerTest#testTopCountWithAggregatedMember2
  # Test case for the support of native top count with aggregated measures
  # feeding the range directly to aggregate.
  it "TopCount with aggregated member feeding range directly" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with
      member Time.x as Aggregate([Time].[1997].[Q1] : [Time].[1997].[Q2], [Measures].[Store Sales])
      member Measures.x1 as ([Time].[1997].[Q1], [Measures].[Store Sales])
      member Measures.x2 as ([Time].[1997].[Q2], [Measures].[Store Sales])
       set products as TopCount(Product.[Product Name].Members, 2, Measures.[Store Sales])
       SELECT NON EMPTY products ON 1,
      NON EMPTY {[Measures].[Store Sales], Measures.x1, Measures.x2} ON 0
      FROM [Sales] where Time.x
    MDX
      Axis #0:
      {[Time].[x]}
      Axis #1:
      {[Measures].[Store Sales]}
      {[Measures].[x1]}
      {[Measures].[x2]}
      Axis #2:
      {[Product].[Food].[Eggs].[Eggs].[Eggs].[Urban].[Urban Small Eggs]}
      {[Product].[Food].[Snack Foods].[Snack Foods].[Dried Fruit].[Fort West].[Fort West Raspberry Fruit Roll]}
      Row #0: 497.42
      Row #0: 235.62
      Row #0: 261.80
      Row #1: 462.84
      Row #1: 226.20
      Row #1: 236.64
    RESULT
  end

  # Java: CompoundSlicerTest#testTopCountWithAggregatedMemberEnumCMSet
  # Test case for the support of native top count with aggregated measures
  # using enumerated members in a calculated member.
  it "TopCount with aggregated member using enumerated calculated member set" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with set TO_AGGREGATE as '{[Time].[1997].[Q1] , [Time].[1997].[Q2]}'
      member Time.x as Aggregate(TO_AGGREGATE, [Measures].[Store Sales])
      member Measures.x1 as ([Time].[1997].[Q1], [Measures].[Store Sales])
      member Measures.x2 as ([Time].[1997].[Q2], [Measures].[Store Sales])
       set products as TopCount(Product.[Product Name].Members, 2, Measures.[Store Sales])
       SELECT NON EMPTY products ON 1,
      NON EMPTY {[Measures].[Store Sales], Measures.x1, Measures.x2} ON 0
       FROM [Sales] where Time.x
    MDX
      Axis #0:
      {[Time].[x]}
      Axis #1:
      {[Measures].[Store Sales]}
      {[Measures].[x1]}
      {[Measures].[x2]}
      Axis #2:
      {[Product].[Food].[Eggs].[Eggs].[Eggs].[Urban].[Urban Small Eggs]}
      {[Product].[Food].[Snack Foods].[Snack Foods].[Dried Fruit].[Fort West].[Fort West Raspberry Fruit Roll]}
      Row #0: 497.42
      Row #0: 235.62
      Row #0: 261.80
      Row #1: 462.84
      Row #1: 226.20
      Row #1: 236.64
    RESULT
  end

  # Java: CompoundSlicerTest#testTopCountWithAggregatedMemberEnumSet
  # Test case for the support of native top count with aggregated measures
  # using enumerated members.
  it "TopCount with aggregated member using enumerated set" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with
      member Time.x as Aggregate({[Time].[1997].[Q1] , [Time].[1997].[Q2]}, [Measures].[Store Sales])
      member Measures.x1 as ([Time].[1997].[Q1], [Measures].[Store Sales])
      member Measures.x2 as ([Time].[1997].[Q2], [Measures].[Store Sales])
       set products as TopCount(Product.[Product Name].Members, 2, Measures.[Store Sales])
       SELECT NON EMPTY products ON 1,
      NON EMPTY {[Measures].[Store Sales], Measures.x1, Measures.x2} ON 0
      FROM [Sales] where Time.x
    MDX
      Axis #0:
      {[Time].[x]}
      Axis #1:
      {[Measures].[Store Sales]}
      {[Measures].[x1]}
      {[Measures].[x2]}
      Axis #2:
      {[Product].[Food].[Eggs].[Eggs].[Eggs].[Urban].[Urban Small Eggs]}
      {[Product].[Food].[Snack Foods].[Snack Foods].[Dried Fruit].[Fort West].[Fort West Raspberry Fruit Roll]}
      Row #0: 497.42
      Row #0: 235.62
      Row #0: 261.80
      Row #1: 462.84
      Row #1: 226.20
      Row #1: 236.64
    RESULT
  end

  # Java: CompoundSlicerTest#testTopCountWithAggregatedMember5
  # Test case for the support of native top count with aggregated measures
  # using yet another different format, slightly different results
  it "TopCount with aggregated member variant 5" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with
      member Time.x as Aggregate([Time].[1997].[Q1] : [Time].[1997].[Q2], [Measures].[Store Sales])
      member Measures.x1 as ([Time].[1997].[Q1], [Measures].[Store Sales])
      member Measures.x2 as ([Time].[1997].[Q2], [Measures].[Store Sales])
       set products as TopCount(Product.[Product Name].Members,2,(Measures.[Store Sales],Time.x))
       SELECT NON EMPTY products ON 1,
      NON EMPTY {[Measures].[Store Sales], Measures.x1, Measures.x2} ON 0
      FROM [Sales]
    MDX
      Axis #0:
      {}
      Axis #1:
      {[Measures].[Store Sales]}
      {[Measures].[x1]}
      {[Measures].[x2]}
      Axis #2:
      {[Product].[Food].[Eggs].[Eggs].[Eggs].[Urban].[Urban Small Eggs]}
      {[Product].[Food].[Snack Foods].[Snack Foods].[Dried Fruit].[Fort West].[Fort West Raspberry Fruit Roll]}
      Row #0: 845.24
      Row #0: 235.62
      Row #0: 261.80
      Row #1: 730.80
      Row #1: 226.20
      Row #1: 236.64
    RESULT
  end

  # Java: CompoundSlicerTest#testTopCountWithAggregatedMemberCacheKey
  # Test case for the support of native top count with aggregated measures
  # using the most complex format. We execute 2 queries to make sure Time.x
  # is not member of the cache key.
  it "TopCount with aggregated member cache key validation" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with
      member Time.x as Aggregate({[Time].[1997].[Q1] , [Time].[1997].[Q2]}, [Measures].[Store Sales])
      member Measures.x1 as ([Time].[1997].[Q1], [Measures].[Store Sales])
      member Measures.x2 as ([Time].[1997].[Q2], [Measures].[Store Sales])
       set products as TopCount(Product.[Product Name].Members, 2, Measures.[Store Sales])
       SELECT NON EMPTY products ON 1,
      NON EMPTY {[Measures].[Store Sales], Measures.x1, Measures.x2} ON 0
      FROM [Sales] where Time.x
    MDX
      Axis #0:
      {[Time].[x]}
      Axis #1:
      {[Measures].[Store Sales]}
      {[Measures].[x1]}
      {[Measures].[x2]}
      Axis #2:
      {[Product].[Food].[Eggs].[Eggs].[Eggs].[Urban].[Urban Small Eggs]}
      {[Product].[Food].[Snack Foods].[Snack Foods].[Dried Fruit].[Fort West].[Fort West Raspberry Fruit Roll]}
      Row #0: 497.42
      Row #0: 235.62
      Row #0: 261.80
      Row #1: 462.84
      Row #1: 226.20
      Row #1: 236.64
    RESULT

    assert_query_returns @olap, <<~MDX, <<~RESULT
      with
      member Time.x as Aggregate(Union({[Time].[1997].[Q4]},[Time].[1997].[Q1] : [Time].[1997].[Q2]),[Measures].[Store Sales])
      member Measures.x1 as ([Time].[1997].[Q1],[Measures].[Store Sales])
      member Measures.x2 as ([Time].[1997].[Q2],[Measures].[Store Sales])
       set products as TopCount(Product.[Product Name].Members,2,(Measures.[Store Sales]))
       SELECT NON EMPTY products ON 1,
      NON EMPTY {[Measures].[Store Sales], Measures.x1, Measures.x2} ON 0
      FROM [Sales]
      where  Time.x
    MDX
      Axis #0:
      {[Time].[x]}
      Axis #1:
      {[Measures].[Store Sales]}
      {[Measures].[x1]}
      {[Measures].[x2]}
      Axis #2:
      {[Product].[Drink].[Beverages].[Drinks].[Flavored Drinks].[Washington].[Washington Apple Drink]}
      {[Product].[Food].[Eggs].[Eggs].[Eggs].[Urban].[Urban Small Eggs]}
      Row #0: 737.10
      Row #0: 189.54
      Row #0: 203.58
      Row #1: 729.30
      Row #1: 235.62
      Row #1: 261.80
    RESULT
  end

  # Java: CompoundSlicerTest#testBugMondrian900
  # Test case for Bug MONDRIAN-900,
  # "Filter() function works incorrectly together with WHERE clause"
  it "MONDRIAN-900 Filter with compound slicer" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select NON EMPTY {[Measures].[Unit Sales]} ON COLUMNS,
        Tail(Filter([Customers].[Name].Members, ([Measures].[Unit Sales] IS EMPTY)), 3) ON ROWS
      from [Sales]
      where ([Time].[1997].[Q1].[2] : [Time].[1997].[Q4].[10])
    MDX
      Axis #0:
      {[Time].[1997].[Q1].[2]}
      {[Time].[1997].[Q1].[3]}
      {[Time].[1997].[Q2].[4]}
      {[Time].[1997].[Q2].[5]}
      {[Time].[1997].[Q2].[6]}
      {[Time].[1997].[Q3].[7]}
      {[Time].[1997].[Q3].[8]}
      {[Time].[1997].[Q3].[9]}
      {[Time].[1997].[Q4].[10]}
      Axis #1:
      Axis #2:
      {[Customers].[USA].[WA].[Walla Walla].[Melanie Snow]}
      {[Customers].[USA].[WA].[Walla Walla].[Ramon Williams]}
      {[Customers].[USA].[WA].[Yakima].[Louis Gomez]}
    RESULT
  end

  # Java: CompoundSlicerTest#testSlicerWithCalcMembers
  it "slicer with calculated members" do
    # 2 calc mems
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH
      MEMBER [Store].[aggCA] AS
      'Aggregate({[Store].[USA].[CA].[Los Angeles], [Store].[USA].[CA].[San Francisco]})'
       MEMBER [Store].[aggOR] AS
      'Aggregate({[Store].[USA].[OR].[Portland]})'
       SELECT FROM SALES WHERE { [Store].[aggCA], [Store].[aggOR] }
    MDX
      Axis #0:
      {[Store].[aggCA]}
      {[Store].[aggOR]}
      53,859
    RESULT

    # mix calc and non-calc
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH
      MEMBER [Store].[aggCA] AS
      'Aggregate({[Store].[USA].[CA].[Los Angeles], [Store].[USA].[CA].[San Francisco]})'
       SELECT FROM SALES WHERE { [Store].[aggCA], [Store].[All Stores].[USA].[OR].[Portland] }
    MDX
      Axis #0:
      {[Store].[aggCA]}
      {[Store].[USA].[OR].[Portland]}
      53,859
    RESULT

    # multi-position slicer with mix of calc and non-calc
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH
      MEMBER [Store].[aggCA] AS
      'Aggregate({[Store].[USA].[CA].[Los Angeles], [Store].[USA].[CA].[San Francisco]})'
       SELECT FROM SALES WHERE
      Gender.Gender.members *
      { [Store].[aggCA], [Store].[All Stores].[USA].[OR].[Portland] }
    MDX
      Axis #0:
      {[Gender].[F], [Store].[aggCA]}
      {[Gender].[F], [Store].[USA].[OR].[Portland]}
      {[Gender].[M], [Store].[aggCA]}
      {[Gender].[M], [Store].[USA].[OR].[Portland]}
      53,859
    RESULT

    # named set with calc mem and non-calc
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with member Time.aggTime as
      'aggregate({ [Time].[1997].[Q1], [Time].[1997].[Q2] })'
      set [timeMembers] as
      '{Time.aggTime, [Time].[1997].[Q3] }'
      select from sales where [timeMembers]
    MDX
      Axis #0:
      {[Time].[aggTime]}
      {[Time].[1997].[Q3]}
      194,749
    RESULT

    # calculated measure in slicer
    assert_query_returns @olap, <<~MDX, <<~RESULT
       SELECT FROM SALES WHERE
      [Measures].[Profit] * { [Store].[USA].[CA], [Store].[USA].[OR]}
    MDX
      Axis #0:
      {[Measures].[Profit], [Store].[USA].[CA]}
      {[Measures].[Profit], [Store].[USA].[OR]}
      $181,141.98
    RESULT
  end

  # Java: CompoundSlicerTest#testCompoundSlicerAndNamedSet
  it "compound slicer and named set" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      WITH SET [aSet] as 'Filter( Except([Store].[Store Country].Members, [Store].[Store Country].[Canada]), Measures.[Store Sales] > 0)'
      SELECT
        { Measures.[Unit Sales] } ON COLUMNS,
        [aSet] ON ROWS
      FROM [Sales]
      WHERE CrossJoin( {[Product].[Drink]}, { [Time].[1997].[Q2], [Time].[1998].[Q1]} )
    MDX
      Axis #0:
      {[Product].[Drink], [Time].[1997].[Q2]}
      {[Product].[Drink], [Time].[1998].[Q1]}
      Axis #1:
      {[Measures].[Unit Sales]}
      Axis #2:
      {[Store].[USA]}
      Row #0: 5,895
    RESULT
  end

  # Java: CompoundSlicerTest#testDistinctCountMeasureInSlicer
  it "distinct count measure in slicer" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      select gender.members on 0
      from sales where
      NonEmptyCrossJoin(Measures.[Customer Count],
      {Time.[1997].Q1, Time.[1997].Q2})
    MDX
      Axis #0:
      {[Measures].[Customer Count], [Time].[1997].[Q1]}
      {[Measures].[Customer Count], [Time].[1997].[Q2]}
      Axis #1:
      {[Gender].[All Gender]}
      {[Gender].[F]}
      {[Gender].[M]}
      Row #0: 4,257
      Row #0: 2,095
      Row #0: 2,162
    RESULT
  end

  # Java: CompoundSlicerTest#testDistinctCountWithAggregateMembersAndCompSlicer
  it "distinct count with aggregate members and compound slicer" do
    assert_query_returns @olap, <<~MDX, <<~RESULT
      with member time.agg as 'Aggregate({Time.[1997].Q1, Time.[1997].Q2})'
      member Store.agg as 'Aggregate(Head(Store.[USA].children,2))'
      select NON EMPTY CrossJoin( time.agg, CrossJoin( store.agg, measures.[customer count]))
       on 0 from sales
      WHERE CrossJoin(Gender.F,
      {[Education Level].[Bachelors Degree], [Education Level].[Graduate Degree]})
    MDX
      Axis #0:
      {[Gender].[F], [Education Level].[Bachelors Degree]}
      {[Gender].[F], [Education Level].[Graduate Degree]}
      Axis #1:
      {[Time].[agg], [Store].[agg], [Measures].[Customer Count]}
      Row #0: 450
    RESULT
  end

  # Java: CompoundSlicerTest#testVirtualCubeWithCountDistinctUnsatisfiable
  it "virtual cube with count distinct unsatisfiable" do
    olap = virtual_cube_with_dc
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        select {measures.[Customer Count],
        measures.[Unit Sales by Customer]} on 0 from [warehouse and sales]
        WHERE {[Time].[1997].Q1, [Time].[1997].Q2}
        *{[Warehouse].[USA].[CA], Warehouse.[USA].[WA]}
      MDX
        Axis #0:
        {[Time].[1997].[Q1], [Warehouse].[USA].[CA]}
        {[Time].[1997].[Q1], [Warehouse].[USA].[WA]}
        {[Time].[1997].[Q2], [Warehouse].[USA].[CA]}
        {[Time].[1997].[Q2], [Warehouse].[USA].[WA]}
        Axis #1:
        {[Measures].[Customer Count]}
        {[Measures].[Unit Sales by Customer]}
        Row #0: #{" "}
        Row #0: #{" "}
      RESULT
    ensure
      olap.close
    end
  end

  # Java: CompoundSlicerTest#testVirtualCubeWithCountDistinctSatisfiable
  it "virtual cube with count distinct satisfiable" do
    olap = virtual_cube_with_dc
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        select {measures.[Customer Count],
        measures.[Unit Sales by Customer]} on 0 from [warehouse and sales]
        WHERE {[Time].[1997].Q1, [Time].[1997].Q2}
        *{[Store].[USA].[CA], Store.[USA].[WA]}
      MDX
        Axis #0:
        {[Time].[1997].[Q1], [Store].[USA].[CA]}
        {[Time].[1997].[Q1], [Store].[USA].[WA]}
        {[Time].[1997].[Q2], [Store].[USA].[CA]}
        {[Time].[1997].[Q2], [Store].[USA].[WA]}
        Axis #1:
        {[Measures].[Customer Count]}
        {[Measures].[Unit Sales by Customer]}
        Row #0: 3,311
        Row #0: 29
      RESULT
    ensure
      olap.close
    end
  end

  # Java: CompoundSlicerTest#testVirtualCubeWithCountDistinctPartiallySatisfiable
  it "virtual cube with count distinct partially satisfiable" do
    olap = virtual_cube_with_dc
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        select {measures.[Warehouse Sales],
        measures.[Unit Sales by Customer]} on 0 from [warehouse and sales]
        WHERE {[Time].[1997].Q1, [Time].[1997].Q2}
        *{[Education Level].[Education Level].members}
      MDX
        Axis #0:
        {[Time].[1997].[Q1], [Education Level].[Bachelors Degree]}
        {[Time].[1997].[Q1], [Education Level].[Graduate Degree]}
        {[Time].[1997].[Q1], [Education Level].[High School Degree]}
        {[Time].[1997].[Q1], [Education Level].[Partial College]}
        {[Time].[1997].[Q1], [Education Level].[Partial High School]}
        {[Time].[1997].[Q2], [Education Level].[Bachelors Degree]}
        {[Time].[1997].[Q2], [Education Level].[Graduate Degree]}
        {[Time].[1997].[Q2], [Education Level].[High School Degree]}
        {[Time].[1997].[Q2], [Education Level].[Partial College]}
        {[Time].[1997].[Q2], [Education Level].[Partial High School]}
        Axis #1:
        {[Measures].[Warehouse Sales]}
        {[Measures].[Unit Sales by Customer]}
        Row #0: #{" "}
        Row #0: 30
      RESULT
    ensure
      olap.close
    end
  end

  # Java: CompoundSlicerTest#testCompoundSlicerWithComplexAggregation
  it "compound slicer with complex aggregation" do
    olap = virtual_cube_with_dc
    begin
      assert_query_returns olap, <<~MDX, <<~RESULT
        with
        member time.agg as 'Aggregate( { ( Gender.F, Time.[1997].Q1), (Gender.M, Time.[1997].Q2) })'
        select measures.[customer count] on 0
        from sales
        where {time.agg, Time.[1998]}
      MDX
        Axis #0:
        {[Time].[agg]}
        {[Time].[1998]}
        Axis #1:
        {[Measures].[Customer Count]}
        Row #0: 2,990
      RESULT
    ensure
      olap.close
    end
  end

  # Java: CompoundSlicerTest#testCompoundAggCalcMemberInSlicer1
  it "compound aggregated calculated member in slicer 1" do
    query = <<~MDX
      WITH member store.agg as
      'Aggregate(CrossJoin(Store.[Store Name].members, Gender.F))'
      SELECT filter(customers.[name].members, measures.[unit sales] > 100) on 0
      FROM sales where store.agg
    MDX
    verify_same_native_and_not(query)
  end

  # Java: CompoundSlicerTest#testCompoundAggCalcMemberInSlicer2
  it "compound aggregated calculated member in slicer 2" do
    query = <<~MDX
      WITH member store.agg as
      'Aggregate({ ([Product].[Product Family].[Drink], Time.[1997].[Q1]), ([Product].[Product Family].[Food], Time.[1997].[Q2]) }))'
      SELECT filter(customers.[name].members, measures.[unit sales] > 100) on 0
      FROM sales where store.agg
    MDX
    verify_same_native_and_not(query)
  end

  # Java: CompoundSlicerTest#testNativeFilterWithNullMember
  # The [Store Sqft] attribute includes a null member. This member should not
  # be excluded by the filter function in this query.
  it "native filter with null member" do
    query = <<~MDX
      WITH
      SET [*NATIVE_CJ_SET] AS 'FILTER(FILTER([Store Size in SQFT].[Store Sqft].MEMBERS,[Store Size in SQFT].CURRENTMEMBER.CAPTION NOT MATCHES ("(?i).*20319.*")), NOT ISEMPTY ([Measures].[Unit Sales]))'
      SET [*SORTED_ROW_AXIS] AS 'ORDER([*CJ_ROW_AXIS],[Store Size in SQFT].CURRENTMEMBER.ORDERKEY,BASC)'
      SET [*BASE_MEMBERS__Measures_] AS '{[Measures].[*FORMATTED_MEASURE_0]}'
      SET [*BASE_MEMBERS__Store Size in SQFT_] AS 'FILTER([Store Size in SQFT].[Store Sqft].MEMBERS,[Store Size in SQFT].CURRENTMEMBER.CAPTION NOT MATCHES ("(?i).*20319.*"))'
      SET [*CJ_ROW_AXIS] AS 'GENERATE([*NATIVE_CJ_SET], {([Store Size in SQFT].CURRENTMEMBER)})'
      MEMBER [Measures].[*FORMATTED_MEASURE_0] AS '[Measures].[Unit Sales]', FORMAT_STRING = 'Standard', SOLVE_ORDER=500
      SELECT
      [*BASE_MEMBERS__Measures_] ON COLUMNS
      ,[*SORTED_ROW_AXIS] ON ROWS
      FROM [Sales]
    MDX
    verify_same_native_and_not(query)
  end
end
