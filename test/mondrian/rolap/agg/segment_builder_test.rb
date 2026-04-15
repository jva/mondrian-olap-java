# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/rolap/agg/SegmentBuilderTest.java
describe "SegmentBuilder" do
  SegmentBuilder = Java::MondrianRolapAgg::SegmentBuilder
  SegmentHeader = Java::MondrianSpi::SegmentHeader
  SegmentBody = Java::MondrianSpi::SegmentBody
  SegmentColumn = Java::MondrianSpi::SegmentColumn
  DenseObjectSegmentBody = Java::MondrianRolapAgg::DenseObjectSegmentBody
  DenseIntSegmentBody = Java::MondrianRolapAgg::DenseIntSegmentBody
  DenseDoubleSegmentBody = Java::MondrianRolapAgg::DenseDoubleSegmentBody
  SparseSegmentBody = Java::MondrianRolapAgg::SparseSegmentBody
  RolapAggregator = Java::MondrianRolap::RolapAggregator
  Datatype = Java::MondrianSpi::Dialect::Datatype
  BitKey = Java::MondrianRolap::BitKey
  ByteString = Java::MondrianUtil::ByteString
  Pair = Java::MondrianUtil::Pair
  RolapUtil = Java::MondrianRolap::RolapUtil

  MOCK_CELL_VALUE = 123.123

  # Cache reflection-based constructors for package-private classes
  DENSE_OBJECT_CONSTRUCTOR = DenseObjectSegmentBody.java_class.getDeclaredConstructors.first.tap { |c| c.setAccessible(true) }
  DENSE_INT_CONSTRUCTOR = DenseIntSegmentBody.java_class.getDeclaredConstructors.first.tap { |c| c.setAccessible(true) }

  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  after do
    RolapUtil.setHook(nil)
  end

  # --- Helper methods ---

  def to_sorted_set(*comparables)
    java.util.TreeSet.new(java.util.Arrays.asList(*comparables))
  end

  def dummy_column_values(cols, num_vals)
    Array.new(cols) do |i|
      Array.new(num_vals) { |j| "c#{i}v#{j}" }
    end
  end

  def make_dummy_segment_header(constrained_columns)
    SegmentHeader.new(
      "dummySchemaName",
      ByteString.new([0].to_java(:byte)),
      "dummyCubeName",
      "dummyMeasureName",
      constrained_columns,
      java.util.Collections.emptyList,
      "dummyFactTable",
      BitKey::Factory.makeBitKey(3),
      java.util.Collections.emptyList
    )
  end

  def make_dummy_header_body_pair(col_exps, col_vals, num_cell_vals, wildcard_cols, null_axis_flags)
    constrained_columns = java.util.ArrayList.new
    axes = java.util.ArrayList.new

    col_vals.each_with_index do |vals, i|
      col_exp = col_exps[i]
      sorted_vals = to_sorted_set(*vals)
      header_vals = wildcard_cols ? nil : sorted_vals
      null_axis_flag = null_axis_flags && null_axis_flags[i] ? true : false

      constrained_columns.add(
        SegmentColumn.new(col_exp, vals.length, header_vals)
      )
      axes.add(Pair.of(sorted_vals, java.lang.Boolean.new(null_axis_flag)))
    end

    cells = java.lang.Object[num_cell_vals].new
    num_cell_vals.times do |i|
      cells[i] = java.lang.Double.new(MOCK_CELL_VALUE)
    end

    Pair.of(
      make_dummy_segment_header(constrained_columns),
      DENSE_OBJECT_CONSTRUCTOR.newInstance(cells, axes)
    )
  end

  def make_segment_map(col_names, col_vals, num_vals_per_col, num_populated_cells, wildcard_cols, null_axis_flags)
    col_vals ||= dummy_column_values(col_names.length, num_vals_per_col)

    header_body = make_dummy_header_body_pair(
      col_names, col_vals, num_populated_cells, wildcard_cols, null_axis_flags
    )
    map = java.util.HashMap.new
    map.put(header_body.left, header_body.right)
    map
  end

  def assert_arrays_are_equal(expected, actual)
    assert_equal expected.length, actual.length,
      "Expected double array: #{expected.to_a}, but got #{actual.to_a}"
    expected.each_with_index do |exp, i|
      assert (actual[i] - exp).abs < 0.00000001,
        "Expected double array: #{expected.to_a}, but got #{actual.to_a}"
    end
  end

  def remove_jdk_dependent_strings(data)
    data.gsub(/^Checksum:.*\r?\n?/, "")
        .gsub(/^ID:.*\r?\n?/, "")
  end

  # Get segment cache from a connection.
  def get_composite_cache(olap)
    connection = olap.raw_mondrian_connection
    server = connection.getServer
    server.getAggregationManager.cacheMgr.compositeCache
  end

  # Create a map with ordered entrySet for deterministic rollup testing.
  # The order parameter controls whether entries are sorted forward or reverse
  # by SegmentHeader uniqueID.
  def get_reversible_test_map(olap, reverse: false)
    cache = get_composite_cache(olap)
    headers = cache.getSegmentHeaders

    entries = []
    headers.each do |header|
      body = cache.get(header)
      entries << [header, body] if body
    end

    refute entries.empty?,
      "SegmentMap is empty. No segmentIds matched test parameters. Full segment cache: #{headers}"

    # Sort by uniqueID
    entries.sort_by! { |header, _body| header.getUniqueID }
    entries.reverse! if reverse

    # Use a LinkedHashMap to preserve insertion order
    map = java.util.LinkedHashMap.new
    entries.each { |header, body| map.put(header, body) }
    map
  end

  def load_cache_with_queries(queries)
    Mondrian::OLAP::Connection.flush_schema_cache
    olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
    queries.each { |query| olap.execute(query) }
    olap
  end

  # Loads the cache with the results of the queries, then attempts to rollup
  # all cached segments based on the keep_columns array, checking against
  # expected_header. Rolls up loading segments in both forward and reverse
  # order and verifies same results both ways.
  def run_rollup_test(cache_populating_queries, keep_columns, expected_header)
    with_properties(OptimizePredicates: false) do
      olap_forward = load_cache_with_queries(cache_populating_queries)
      begin
        map = get_reversible_test_map(olap_forward, reverse: false)
        keep_set = java.util.HashSet.new(java.util.Arrays.asList(*keep_columns))
        rolled_forward = SegmentBuilder.rollup(
          map, keep_set,
          BitKey::Factory.makeBitKey(java.util.BitSet.new),
          RolapAggregator::Sum, Datatype::Numeric
        )
      ensure
        olap_forward.close
      end

      olap_reverse = load_cache_with_queries(cache_populating_queries)
      begin
        map = get_reversible_test_map(olap_reverse, reverse: true)
        rolled_reverse = SegmentBuilder.rollup(
          map, keep_set,
          BitKey::Factory.makeBitKey(java.util.BitSet.new),
          RolapAggregator::Sum, Datatype::Numeric
        )
      ensure
        olap_reverse.close
      end

      assert_equal expected_header, remove_jdk_dependent_strings(rolled_forward.getKey.toString)
      # The header of the rolled up segment should be the same
      # regardless of the order the segments were processed
      assert_equal rolled_forward.getKey, rolled_reverse.getKey
      assert_equal rolled_forward.getValue.getValueMap.size,
        rolled_reverse.getValue.getValueMap.size

      rolled_forward
    end
  end

  # --- Direct SegmentBuilder.rollup tests ---

  # Java: SegmentBuilderTest#testRollupWithNullAxisVals
  it "rollup with null axis vals" do
    # Perform two rollups. One with two columns each containing 3 values.
    # The second with two columns containing 2 values + null.
    # The rolled up values should be equal in the two cases.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      rollup_no_nulls = SegmentBuilder.rollup(
        make_segment_map(
          %w[col1 col2], nil, 3, 9, true,
          [false, false]),  # each axis sets null axis flag=F
        java.util.Collections.singleton("col2"),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )

      rollup_with_null_members = SegmentBuilder.rollup(
        make_segment_map(
          %w[col1 col2], nil, 2, 9, true,
          [true, true]),  # each axis sets null axis flag=T
        java.util.Collections.singleton("col2"),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )

      assert_arrays_are_equal(
        rollup_no_nulls.getValue.getValueArray.to_a,
        rollup_with_null_members.getValue.getValueArray.to_a
      )

      null_flags = rollup_with_null_members.getValue.getNullAxisFlags
      assert_equal 1, null_flags.length, "Rolled up column should have nullAxisFlag set."
      assert_equal true, null_flags[0], "Rolled up column should have nullAxisFlag set."

      assert_equal "col2",
        rollup_with_null_members.getKey.getConstrainedColumns.get(0).columnExpression
    end
  end

  # Java: SegmentBuilderTest#testRollupWithMixOfNullAxisValues
  it "rollup with mix of null axis values" do
    # Constructed segment has 3 columns:
    #    2 values in the first
    #    2 values + null in the second and third
    #  = 18 values
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      rollup = SegmentBuilder.rollup(
        make_segment_map(
          %w[col1 col2 col3], nil, 2, 18, true,
          [false, true, true]),  # col2 & col3 have nullAxisFlag=T
        java.util.Collections.singleton("col2"),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )

      # Expected value is 6 * MOCK_CELL_VALUE for each of 3 column values,
      # since each of the 18 cells are being rolled up to 3 buckets
      expected_val = 6 * MOCK_CELL_VALUE
      assert_arrays_are_equal(
        [expected_val, expected_val, expected_val],
        rollup.getValue.getValueArray.to_a
      )

      null_flags = rollup.getValue.getNullAxisFlags
      assert_equal 1, null_flags.length, "Rolled up column should have nullAxisFlag set."
      assert_equal true, null_flags[0], "Rolled up column should have nullAxisFlag set."

      assert_equal "col2",
        rollup.getKey.getConstrainedColumns.get(0).columnExpression
    end
  end

  # Java: SegmentBuilderTest#testRollup2ColumnsWithMixOfNullAxisValues
  it "rollup 2 columns with mix of null axis values" do
    # Constructed segment has 3 columns:
    #    2 values in the first
    #    2 values + null in the second and third
    #  = 18 values
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      rollup = SegmentBuilder.rollup(
        make_segment_map(
          %w[col1 col2 col3], nil, 2, 12, true,
          [false, true, false]),  # col2 has nullAxisFlag=T
        java.util.HashSet.new(java.util.Arrays.asList("col1", "col2")),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )

      # Expected value is 2 * MOCK_CELL_VALUE for each of 6 column value
      # combinations, since each of the 12 cells are being rolled up to
      # 3 * 2 buckets
      expected_val = 2 * MOCK_CELL_VALUE
      assert_arrays_are_equal(
        [expected_val] * 6,
        rollup.getValue.getValueArray.to_a
      )

      null_flags = rollup.getValue.getNullAxisFlags
      assert_equal 2, null_flags.length,
        "Rolled up column should have nullAxisFlag set to false for the first column, true for second column."
      assert_equal false, null_flags[0]
      assert_equal true, null_flags[1]

      assert_equal "col1",
        rollup.getKey.getConstrainedColumns.get(0).columnExpression
      assert_equal "col2",
        rollup.getKey.getConstrainedColumns.get(1).columnExpression
    end
  end

  # Java: SegmentBuilderTest#testMultiSegRollupWithMixOfNullAxisValues
  it "multi-segment rollup with mix of null axis values" do
    # Rolls up 2 segments.
    # Segment 1 has 3 columns:
    #    2 values in the first
    #    1 values + null in the second
    #    2 vals + null in the third
    #  = 12 values
    # Segment 2 has the same 3 columns, different values for 3rd column.
    #
    # None of the columns are wildcarded.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      map = make_segment_map(
        %w[col1 col2 col3],
        [%w[col1A col1B], %w[col2A], %w[col3A col3B]],
        -1, 12, false,
        [false, true, true]  # col2 & col3 have nullAxisFlag=T
      )
      map.putAll(
        make_segment_map(
          %w[col1 col2 col3],
          [%w[col1A col1B], %w[col2A], %w[col3C col3D]],
          -1, 8, false,
          [false, true, false]  # col3 has nullAxisFlag=T
        )
      )

      rollup = SegmentBuilder.rollup(
        map,
        java.util.Collections.singleton("col2"),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )

      # Expected value is 10 * MOCK_CELL_VALUE for each of 2 column values,
      # since the 20 cells across 2 segments are being rolled up to 2 buckets
      expected_val = 10 * MOCK_CELL_VALUE
      assert_arrays_are_equal(
        [expected_val, expected_val],
        rollup.getValue.getValueArray.to_a
      )

      null_flags = rollup.getValue.getNullAxisFlags
      assert_equal 1, null_flags.length,
        "Rolled up column should have nullAxisFlag set to true for a single column."
      assert_equal true, null_flags[0]

      assert_equal "col2",
        rollup.getKey.getConstrainedColumns.get(0).columnExpression
    end
  end

  # Java: SegmentBuilderTest#testNullMemberOffset
  it "null member offset" do
    # Verifies that presence of a null member does not cause
    # offsets to be incorrect for a Segment rollup.
    # First query loads the cache with a segment that can fulfill the
    # second query.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      Mondrian::OLAP::Connection.flush_schema_cache
      olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        olap.execute(
          "select [Store Size in SQFT].[Store Sqft].members * " \
          "gender.gender.members on 0 from sales"
        )
        assert_query_returns olap,
          "select non empty [Store Size in SQFT].[Store Sqft].members on 0 " \
          "from sales",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Store Size in SQFT].[#null]}
            {[Store Size in SQFT].[20319]}
            {[Store Size in SQFT].[21215]}
            {[Store Size in SQFT].[22478]}
            {[Store Size in SQFT].[23598]}
            {[Store Size in SQFT].[23688]}
            {[Store Size in SQFT].[27694]}
            {[Store Size in SQFT].[28206]}
            {[Store Size in SQFT].[30268]}
            {[Store Size in SQFT].[33858]}
            {[Store Size in SQFT].[39696]}
            Row #0: 39,329
            Row #0: 26,079
            Row #0: 25,011
            Row #0: 2,117
            Row #0: 25,663
            Row #0: 21,333
            Row #0: 41,580
            Row #0: 2,237
            Row #0: 23,591
            Row #0: 35,257
            Row #0: 24,576
          RESULT
      ensure
        olap.close
      end
    end
  end

  # Java: SegmentBuilderTest#testNullMemberOffset2ColRollup
  it "null member offset 2 column rollup" do
    # Verifies that presence of a null member does not cause
    # offsets to be incorrect for a Segment rollup involving 2
    # columns. This tests a case where
    # SegmentBuilder.computeAxisMultipliers needs to factor in
    # the null axis flag.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      Mondrian::OLAP::Connection.flush_schema_cache
      olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        olap.execute(
          "select [Store Size in SQFT].[Store Sqft].members * " \
          "[store].[store state].members * time.[quarter].members on 0" \
          " from sales where [Product].[Food].[Produce].[Vegetables].[Fresh Vegetables]"
        )
        assert_query_returns olap,
          "select non empty [Store Size in SQFT].[Store Sqft].members " \
          " * [store].[store state].members  on 0" \
          "from sales where [Product].[Food].[Produce].[Vegetables].[Fresh Vegetables]",
          <<~RESULT
            Axis #0:
            {[Product].[Food].[Produce].[Vegetables].[Fresh Vegetables]}
            Axis #1:
            {[Store Size in SQFT].[#null], [Store].[USA].[CA]}
            {[Store Size in SQFT].[#null], [Store].[USA].[WA]}
            {[Store Size in SQFT].[20319], [Store].[USA].[OR]}
            {[Store Size in SQFT].[21215], [Store].[USA].[WA]}
            {[Store Size in SQFT].[22478], [Store].[USA].[CA]}
            {[Store Size in SQFT].[23598], [Store].[USA].[CA]}
            {[Store Size in SQFT].[23688], [Store].[USA].[CA]}
            {[Store Size in SQFT].[27694], [Store].[USA].[OR]}
            {[Store Size in SQFT].[28206], [Store].[USA].[WA]}
            {[Store Size in SQFT].[30268], [Store].[USA].[WA]}
            {[Store Size in SQFT].[33858], [Store].[USA].[WA]}
            {[Store Size in SQFT].[39696], [Store].[USA].[WA]}
            Row #0: 1,967
            Row #0: 947
            Row #0: 2,065
            Row #0: 1,827
            Row #0: 165
            Row #0: 2,109
            Row #0: 1,665
            Row #0: 3,382
            Row #0: 162
            Row #0: 1,875
            Row #0: 2,668
            Row #0: 1,907
          RESULT
      ensure
        olap.close
      end
    end
  end

  # Java: SegmentBuilderTest#testSegmentBodyIterator
  it "segment body iterator" do
    # Checks that cell key coordinates are generated correctly
    # when a null member is present.
    axes = java.util.ArrayList.new
    axes.add(Pair.of(
      java.util.TreeSet.new(java.util.Arrays.asList("foo1", "bar1")),
      java.lang.Boolean.new(true)))  # nullAxisFlag=T
    axes.add(Pair.of(
      java.util.TreeSet.new(java.util.Arrays.asList("foo2", "bar2", "baz3")),
      java.lang.Boolean.new(false)))

    test_body = DENSE_INT_CONSTRUCTOR.newInstance(
      java.util.BitSet.new,
      [1, 2, 3, 4, 5, 6, 7, 8, 9].to_java(:int),
      axes
    )
    value_map = test_body.getValueMap
    assert_equal(
      "{(0, 0)=1, (0, 1)=2, (0, 2)=3, (1, 0)=4, (1, 1)=5, (1, 2)=6, (2, 0)=7, (2, 1)=8, (2, 2)=9}",
      value_map.toString
    )
  end

  # Java: SegmentBuilderTest#testSparseRollup
  it "sparse rollup" do
    # Functional test for a case that causes OOM if rollup creates
    # a dense segment.
    # This test is guarded by PerformanceTest.LOGGER.isDebugEnabled()
    # in Java; skip in Ruby since debug logging is not typically enabled.
    skip "Performance test: only runs when PerformanceTest LOGGER debug is enabled"
  end

  # Java: SegmentBuilderTest#testRollupWithIntOverflowPossibility
  it "rollup with int overflow possibility" do
    # Rolling up a segment that would cause int overflow if
    # rolled up to a dense segment
    # MONDRIAN-1377
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      # Make a source segment w/ 3 cols, 47K vals each,
      # target segment has 2 of the 3 cols.
      # Count of possible values will exceed Integer.MAX_VALUE
      rollup = SegmentBuilder.rollup(
        make_segment_map(
          %w[col1 col2 col3], nil, 47_000, 4, false, nil),
        java.util.HashSet.new(java.util.Arrays.asList("col1", "col2")),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )
      assert_kind_of SparseSegmentBody, rollup.right.java_object
    end
  end

  # Java: SegmentBuilderTest#testRollupWithOOMPossibility
  it "rollup with OOM possibility" do
    # Rolling up a segment that would cause OOM if
    # rolled up to a dense segment
    # MONDRIAN-1377
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      # Make a source segment w/ 3 cols, 44K vals each,
      # target segment has 2 of the 3 cols.
      rollup = SegmentBuilder.rollup(
        make_segment_map(
          %w[col1 col2 col3], nil, 44_000, 4, false, nil),
        java.util.HashSet.new(java.util.Arrays.asList("col1", "col2")),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )
      assert_kind_of SparseSegmentBody, rollup.right.java_object
    end
  end

  # Java: SegmentBuilderTest#testRollupShouldBeDense
  it "rollup should be dense" do
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      # Fewer than 1000 column values in rolled up segment.
      rollup = SegmentBuilder.rollup(
        make_segment_map(
          %w[col1 col2 col3], nil, 10, 15, false, nil),
        java.util.HashSet.new(java.util.Arrays.asList("col1", "col2")),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )
      assert_kind_of DenseDoubleSegmentBody, rollup.right.java_object

      # Greater than 1K col vals, above density ratio
      rollup = SegmentBuilder.rollup(
        make_segment_map(
          %w[col1 col2 col3 col4], nil, 11, 10_000, false, nil),
        # 1331 possible intersections (11**3)
        java.util.HashSet.new(java.util.Arrays.asList("col1", "col2", "col3")),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )
      assert_kind_of DenseDoubleSegmentBody, rollup.right.java_object
    end
  end

  # Java: SegmentBuilderTest#testRollupWithDenseIntBody
  it "rollup with dense int body" do
    # We have the following data:
    #
    #           1 _ _
    #    col2   1 2 _
    #           1 _ 1
    #            col1
    #   So, after rolling it up with the SUM function, we expect to get
    #
    #           3 2 1
    #            col1
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      col_values = dummy_column_values(2, 3)
      values = [1, 1, 1, 0, 2, 0, 1]

      nulls = java.util.BitSet.new
      values.each_with_index do |v, i|
        nulls.set(i) if v == 0
      end

      axes = java.util.ArrayList.new
      segment_columns = java.util.ArrayList.new
      col_values.each_with_index do |vals, i|
        sorted = to_sorted_set(*vals)
        axes.add(Pair.of(sorted, java.lang.Boolean.new(false)))
        segment_columns.add(SegmentColumn.new("col#{i + 1}", vals.length, sorted))
      end

      header = make_dummy_segment_header(segment_columns)
      body = DENSE_INT_CONSTRUCTOR.newInstance(nulls, values.to_java(:int), axes)
      segments_map = java.util.Collections.singletonMap(header, body)

      rollup = SegmentBuilder.rollup(
        segments_map, java.util.Collections.singleton("col1"),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )

      result = rollup.right.getValueArray.to_a
      expected = [3.0, 2.0, 1.0]
      assert_equal expected.length, result.length
      expected.each_with_index do |exp, i|
        assert (exp - result[i]).abs < 1e-6,
          "#{i} #{exp} #{result[i]}"
      end
    end
  end

  # Java: SegmentBuilderTest#testOverlappingSegments
  it "overlapping segments" do
    # MONDRIAN-2107
    # The segments created by the first 2 queries below overlap on
    # [1997].[Q1].[1]. The rollup of these two segments should not
    # doubly-add that cell.
    # Also, these two segments have predicates optimized for 'quarter'
    # since 3 out of 4 quarters are present. This means the
    # header.getValues() will be null. This has the potential
    # to cause issues with rollup since one segment body will have
    # 3 values for quarter, the other segment body will have a different
    # set of values.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      Mondrian::OLAP::Connection.flush_schema_cache
      olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        olap.execute(
          "select " \
          "{[Time].[1997].[Q1].[1], [Time].[1997].[Q1].[2], [Time].[1997].[Q1].[3], " \
          "[Time].[1997].[Q2].[4], [Time].[1997].[Q2].[5], [Time].[1997].[Q2].[6]," \
          "[Time].[1997].[Q3].[7]} on 0 from sales"
        )
        olap.execute(
          "select " \
          "{[Time].[1997].[Q1].[1], [Time].[1997].[Q3].[8], [Time].[1997].[Q3].[9], " \
          "[Time].[1997].[Q4].[10], [Time].[1997].[Q4].[11], [Time].[1997].[Q4].[12]," \
          "[Time].[1998].[Q1].[1], [Time].[1998].[Q3].[8], [Time].[1998].[Q3].[9], " \
          "[Time].[1998].[Q4].[10], [Time].[1998].[Q4].[11], [Time].[1998].[Q4].[12]}" \
          "on 0 from sales"
        )

        # Set a hook to verify we do not see SQL with sum(unit_sales)
        # if cache rollup is working
        hook = Class.new do
          include RolapUtil::ExecuteQueryHook
          def initialize
            @sql_seen = java.util.concurrent.CopyOnWriteArrayList.new
          end
          attr_reader :sql_seen
          def onExecuteQuery(sql)
            @sql_seen << sql
          end
        end.new
        RolapUtil.setHook(hook)

        assert_query_returns olap,
          "select [Time].[1997].children on 0 from sales",
          <<~RESULT
            Axis #0:
            {}
            Axis #1:
            {[Time].[1997].[Q1]}
            {[Time].[1997].[Q2]}
            {[Time].[1997].[Q3]}
            {[Time].[1997].[Q4]}
            Row #0: 66,291
            Row #0: 62,610
            Row #0: 65,848
            Row #0: 72,024
          RESULT

        # Note: hook.sql_seen may be empty if cache rollup serves the query without SQL.
        # The refute_match loop then passes vacuously, matching Java behavior where the inline
        # assertFalse also never fires.
        hook.sql_seen.each do |sql|
          refute_match(/sum\([^ ]+unit_sales/, sql, "Expected cells to be pulled from cache")
        end
      ensure
        olap.close
      end
    end
  end

  # Java: SegmentBuilderTest#testNonOverlappingRollupWithUnconstrainedColumn
  it "non-overlapping rollup with unconstrained column" do
    # MONDRIAN-2107
    # The two segments loaded by the 1st 2 queries will have predicates
    # optimized for Name. Prior to the fix for 2107 this would
    # result in roughly half of the customers having empty results
    # for the 3rd query, since the values of only one of the two
    # segments would be loaded into the AxisInfo.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      query = "select customers.[name].members on 0 from sales"

      # Get baseline result without in-memory rollup
      Mondrian::OLAP::Connection.flush_schema_cache
      olap_baseline = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        with_properties(EnableInMemoryRollup: false) do
          baseline_result = format_result(olap_baseline.execute(query))

          Mondrian::OLAP::Connection.flush_schema_cache
          olap_test = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
          begin
            with_properties(EnableInMemoryRollup: true) do
              olap_test.execute(
                "select {[customers].[name].members} on 0 from sales where gender.f"
              )
              olap_test.execute(
                "select {[customers].[name].members} on 0 from sales where gender.m"
              )

              hook = Class.new do
                include RolapUtil::ExecuteQueryHook
                def initialize
                  @sql_seen = java.util.concurrent.CopyOnWriteArrayList.new
                end
                attr_reader :sql_seen
                def onExecuteQuery(sql)
                  @sql_seen << sql
                end
              end.new
              RolapUtil.setHook(hook)

              actual_result = format_result(olap_test.execute(query))

              # Note: hook.sql_seen may be empty if cache rollup serves the query without SQL.
              # The refute_match loop then passes vacuously, matching Java behavior where the inline
              # assertFalse also never fires.
              hook.sql_seen.each do |sql|
                refute_match(/sum\([^ ]+unit_sales/, sql, "Expected cells to be pulled from cache")
              end

              assert_like baseline_result, actual_result
            end
          ensure
            olap_test.close
          end
        end
      ensure
        olap_baseline.close
      end
    end
  end

  # Java: SegmentBuilderTest#testNonOverlappingRollupWithUnconstrainedColumnAndHasNull
  it "non-overlapping rollup with unconstrained column and has null" do
    # MONDRIAN-2107
    # Creates 10 segments, one for each city, with various sets
    # of [Store Sqft]. Some contain NULL, some do not.
    # Results from rollup should match results from a query not pulling
    # from cache.
    states = [
      "[Canada].BC", "[USA].CA", "[Mexico].DF",
      "[Mexico].Guerrero", "[Mexico].Jalisco", "[USA].[OR]",
      "[Mexico].Veracruz", "[USA].WA", "[Mexico].Yucatan",
      "[Mexico].Zacatecas"
    ]

    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      query = "select [Store Size in SQFT].[Store Sqft].members on 0 from sales"

      Mondrian::OLAP::Connection.flush_schema_cache
      olap_baseline = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        baseline_result = format_result(olap_baseline.execute(query))

        Mondrian::OLAP::Connection.flush_schema_cache
        olap_test = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
        begin
          states.each do |state|
            olap_test.execute(
              "select {[Store Size in SQFT].[Store Sqft].members} on 0 " \
              "from sales where store.#{state}"
            )
          end

          hook = Class.new do
            include RolapUtil::ExecuteQueryHook
            def initialize
              @sql_seen = java.util.concurrent.CopyOnWriteArrayList.new
            end
            attr_reader :sql_seen
            def onExecuteQuery(sql)
              @sql_seen << sql
            end
          end.new
          RolapUtil.setHook(hook)

          actual_result = format_result(olap_test.execute(query))

          # Note: hook.sql_seen may be empty if cache rollup serves the query without SQL.
          # The refute_match loop then passes vacuously, matching Java behavior where the inline
          # assertFalse also never fires.
          hook.sql_seen.each do |sql|
            refute_match(/sum\([^ ]+unit_sales/, sql, "Expected cell to be pulled from cache")
          end

          assert_like baseline_result, actual_result
        ensure
          olap_test.close
        end
      ensure
        olap_baseline.close
      end
    end
  end

  # Java: SegmentBuilderTest#testBadRollupCausesGreaterThan12Iterations
  it "bad rollup causes greater than 12 iterations" do
    # http://jira.pentaho.com/browse/MONDRIAN-1729
    # The first two queries populate the cache with segments
    # capable of being rolled up to fulfill the 3rd query.
    # MONDRIAN-1729 involved the rollup being invalid, causing
    # an infinite loop.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      Mondrian::OLAP::Connection.flush_schema_cache
      olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        olap.execute(
          "select " \
          "{[Time].[1998].[Q1].[2],[Time].[1998].[Q1].[3]," \
          "[Time].[1998].[Q2].[4],[Time].[1998].[Q2].[5]," \
          "[Time].[1998].[Q2].[5],[Time].[1998].[Q2].[6]," \
          "[Time].[1998].[Q3].[7]} on 0 from sales"
        )

        olap.execute(
          "select " \
          "{[Time].[1997].[Q1].[1], [Time].[1997].[Q3].[8], [Time].[1997].[Q3].[9], " \
          "[Time].[1997].[Q4].[10], [Time].[1997].[Q4].[11], [Time].[1997].[Q4].[12]," \
          "[Time].[1998].[Q1].[1], [Time].[1998].[Q3].[8], [Time].[1998].[Q3].[9], " \
          "[Time].[1998].[Q4].[10], [Time].[1998].[Q4].[11], [Time].[1998].[Q4].[12]}" \
          "on 0 from sales"
        )

        # This should complete without infinite loop
        result = olap.execute("select [Time].[1998].[Q1] on 0 from sales")
        refute_nil result
      ensure
        olap.close
      end
    end
  end

  # Java: SegmentBuilderTest#testSameRollupRegardlessOfSegmentOrderWithEmptySegmentBody
  it "same rollup regardless of segment order with empty segment body" do
    # http://jira.pentaho.com/browse/MONDRIAN-1729
    # Rollup of segments {A, B} should produce the same resulting segment
    # regardless of whether rollup processes them in the order A,B or B,A.
    # MONDRIAN-1729 involved a case where the rollup segment was invalid
    # if processed in a particular order.
    # This tests a wildcarded segment (on year) rolled up w/ a seg
    # containing a single val.
    # The resulting segment contains only empty results (for 1998)
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      run_rollup_test(
        [
          "select " \
          "{[Time].[1998].[Q1].[2],[Time].[1998].[Q1].[3]," \
          "[Time].[1998].[Q2].[4],[Time].[1998].[Q2].[5]," \
          "[Time].[1998].[Q2].[5],[Time].[1998].[Q2].[6]," \
          "[Time].[1998].[Q3].[7]} on 0 from sales",
          "select " \
          "{[Time].[1997].[Q1].[1], [Time].[1997].[Q3].[8], [Time].[1997].[Q3].[9], " \
          "[Time].[1997].[Q4].[10], [Time].[1997].[Q4].[11], [Time].[1997].[Q4].[12]," \
          "[Time].[1998].[Q1].[1], [Time].[1998].[Q3].[8], [Time].[1998].[Q3].[9], " \
          "[Time].[1998].[Q4].[10], [Time].[1998].[Q4].[11], [Time].[1998].[Q4].[12]}" \
          "on 0 from sales"
        ],
        %w[time_by_day.quarter time_by_day.the_year],
        "*Segment Header\n" \
        "Schema:[FoodMart]\n" \
        "Cube:[Sales]\n" \
        "Measure:[Unit Sales]\n" \
        "Axes:[\n" \
        "    {time_by_day.quarter=('Q1','Q3')}\n" \
        "    {time_by_day.the_year=('1998')}]\n" \
        "Excluded Regions:[]\n" \
        "Compound Predicates:[]\n"
      )
    end
  end

  # Java: SegmentBuilderTest#testSameRollupRegardlessOfSegmentOrderWithData
  it "same rollup regardless of segment order with data" do
    # http://jira.pentaho.com/browse/MONDRIAN-1729
    # Tests a wildcarded segment rolled up w/ a seg containing a single
    # val. Both segments are associated w/ non empty results.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      run_rollup_test(
        [
          "select {{[Product].[Drink].[Alcoholic Beverages]},\n" \
          "{[Product].[Drink].[Beverages]},\n" \
          "{[Product].[Food].[Baked Goods]},\n" \
          "{[Product].[Non-Consumable].[Periodicals]}}\n on 0 from sales",
          "select \n{[Product].[Drink].[Dairy]}on 0 from sales"
        ],
        %w[product_class.product_family],
        "*Segment Header\n" \
        "Schema:[FoodMart]\n" \
        "Cube:[Sales]\n" \
        "Measure:[Unit Sales]\n" \
        "Axes:[\n" \
        "    {product_class.product_family=('Drink')}]\n" \
        "Excluded Regions:[]\n" \
        "Compound Predicates:[]\n"
      )
    end
  end

  # Java: SegmentBuilderTest#testSameRollupRegardlessOfSegmentOrderNoWildcards
  it "same rollup regardless of segment order no wildcards" do
    # http://jira.pentaho.com/browse/MONDRIAN-1729
    # Tests 2 segments, each w/ no wildcarded values.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      run_rollup_test(
        [
          "select {{[Product].[Drink].[Alcoholic Beverages]},\n" \
          "{[Product].[Drink].[Beverages]},\n" \
          "{[Product].[Non-Consumable].[Periodicals]}}\n on 0 from sales",
          "select \n{[Product].[Drink].[Dairy]}on 0 from sales"
        ],
        %w[product_class.product_family],
        "*Segment Header\n" \
        "Schema:[FoodMart]\n" \
        "Cube:[Sales]\n" \
        "Measure:[Unit Sales]\n" \
        "Axes:[\n" \
        "    {product_class.product_family=('Drink')}]\n" \
        "Excluded Regions:[]\n" \
        "Compound Predicates:[]\n"
      )
    end
  end

  # Java: SegmentBuilderTest#testSameRollupRegardlessOfSegmentOrderThreeSegs
  it "same rollup regardless of segment order three segments" do
    # http://jira.pentaho.com/browse/MONDRIAN-1729
    # Tests 3 segments, each w/ no wildcarded values.
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      run_rollup_test(
        [
          "select {{[Product].[Drink].[Alcoholic Beverages]},\n" \
          "{[Product].[Non-Consumable].[Periodicals]}}\n on 0 from sales",
          "select \n{[Product].[Drink].[Dairy]}on 0 from sales",
          " select {[Product].[Drink].[Beverages]} on 0 from sales"
        ],
        %w[product_class.product_family],
        "*Segment Header\n" \
        "Schema:[FoodMart]\n" \
        "Cube:[Sales]\n" \
        "Measure:[Unit Sales]\n" \
        "Axes:[\n" \
        "    {product_class.product_family=('Drink')}]\n" \
        "Excluded Regions:[]\n" \
        "Compound Predicates:[]\n"
      )
    end
  end

  # Java: SegmentBuilderTest#testSegmentCreationForBoolean_True
  it "segment creation for boolean true" do
    unless MONDRIAN_DRIVER == "oracle"
      # Oracle does not support boolean type
      with_properties(
        EnableInMemoryRollup: true,
        EnableNativeNonEmpty: true,
        SparseSegmentDensityThreshold: 0.5,
        SparseSegmentCountThreshold: 1000
      ) do
        Mondrian::OLAP::Connection.flush_schema_cache
        olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
        begin
          olap.execute(
            "SELECT NON EMPTY [Store].[Store Country].members on COLUMNS " \
            "FROM [Store] " \
            "WHERE [Has coffee bar].[true]"
          )

          assert_query_returns olap,
            "SELECT NON EMPTY " \
            "CROSSJOIN([Store].[Store Country].members, [Has coffee bar].[has coffee bar].members) ON COLUMNS " \
            "FROM [Store]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Store].[Canada], [Has coffee bar].[true]}
              {[Store].[Mexico], [Has coffee bar].[false]}
              {[Store].[Mexico], [Has coffee bar].[true]}
              {[Store].[USA], [Has coffee bar].[false]}
              {[Store].[USA], [Has coffee bar].[true]}
              Row #0: 57,564
              Row #0: 133,275
              Row #0: 109,737
              Row #0: 113,881
              Row #0: 157,139
            RESULT
        ensure
          olap.close
        end
      end
    end
  end

  # Java: SegmentBuilderTest#testSegmentCreationForBoolean_False
  it "segment creation for boolean false" do
    unless MONDRIAN_DRIVER == "oracle"
      # Oracle does not support boolean type
      with_properties(
        EnableInMemoryRollup: true,
        EnableNativeNonEmpty: true,
        SparseSegmentDensityThreshold: 0.5,
        SparseSegmentCountThreshold: 1000
      ) do
        Mondrian::OLAP::Connection.flush_schema_cache
        olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
        begin
          olap.execute(
            "SELECT NON EMPTY [Store].[Store Country].members on COLUMNS " \
            "FROM [Store] " \
            "WHERE [Has coffee bar].[false]"
          )

          assert_query_returns olap,
            "SELECT NON EMPTY " \
            "CROSSJOIN([Store].[Store Country].members, [Has coffee bar].[has coffee bar].members) ON COLUMNS " \
            "FROM [Store]",
            <<~RESULT
              Axis #0:
              {}
              Axis #1:
              {[Store].[Canada], [Has coffee bar].[true]}
              {[Store].[Mexico], [Has coffee bar].[false]}
              {[Store].[Mexico], [Has coffee bar].[true]}
              {[Store].[USA], [Has coffee bar].[false]}
              {[Store].[USA], [Has coffee bar].[true]}
              Row #0: 57,564
              Row #0: 133,275
              Row #0: 109,737
              Row #0: 113,881
              Row #0: 157,139
            RESULT
        ensure
          olap.close
        end
      end
    end
  end

  # Java: SegmentBuilderTest#testRollupWithNonUniqueColumns
  it "rollup with non-unique columns" do
    with_properties(
      EnableInMemoryRollup: true,
      EnableNativeNonEmpty: true,
      SparseSegmentDensityThreshold: 0.5,
      SparseSegmentCountThreshold: 1000
    ) do
      rollup = SegmentBuilder.rollup(
        make_segment_map(
          %w[col1 col2 col3 col2],
          [%w[0.0], %w[0.0], %w[0.0], %w[0.0]],
          10, 15, false, nil),
        java.util.HashSet.new(java.util.Arrays.asList("col1", "col2")),
        nil, RolapAggregator::Sum, Datatype::Numeric
      )
      assert_equal 3, rollup.left.getConstrainedColumns.size
    end
  end
end
