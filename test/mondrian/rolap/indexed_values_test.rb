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

# Java: mondrian/rolap/IndexedValuesTest.java
describe "IndexedValues" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close if @olap
  end

  # Create a fresh connection with SsasCompatibleNaming enabled.
  # Yields the connection and ensures cleanup.
  def with_ssas_connection
    with_properties(SsasCompatibleNaming: true) do
      Mondrian::OLAP::Connection.flush_schema_cache
      olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS)
      begin
        yield olap
      ensure
        olap.close
        Mondrian::OLAP::Connection.flush_schema_cache
      end
    end
  end

  # Assert query result with currency normalization.
  # The JVM locale may produce a different currency symbol (e.g. "€")
  # than the Java tests expect ("$"). Normalize to "$" for comparison.
  def assert_query_returns_normalized(olap, mdx, expected)
    result = olap.execute(mdx)
    actual = format_result(result).gsub(/[€£¥]/, '$')
    assert_like expected, actual
  end

  HR_MDX = "SELECT {[Measures].[Org Salary], [Measures].[Count]} " \
    "ON COLUMNS, " \
    "%s " \
    "ON ROWS FROM [HR]"

  # Java: IndexedValuesTest#testQueryWithIndex
  it "query using member names" do
    assert_query_returns_normalized @olap, HR_MDX % "{[Employees].[Sheri Nowmer]}",
      <<~RESULT
        Axis #0:
        {}
        Axis #1:
        {[Measures].[Org Salary]}
        {[Measures].[Count]}
        Axis #2:
        {[Employees].[Sheri Nowmer]}
        Row #0: $39,431.67
        Row #0: 7,392
      RESULT
  end

  # Java: IndexedValuesTest#testQueryWithIndex
  it "query using member key with &[key] syntax requires SsasCompatibleNaming" do
    with_ssas_connection do |olap|
      assert_query_returns_normalized olap, HR_MDX % "{[Employees].&[1]}",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Org Salary]}
          {[Measures].[Count]}
          Axis #2:
          {[Employees].[Sheri Nowmer]}
          Row #0: $39,431.67
          Row #0: 7,392
        RESULT
    end
  end

  # Java: IndexedValuesTest#testQueryWithIndex
  # Cannot find members that are not at root of hierarchy.
  # (We should fix this.)
  it "query using member key for non-root member" do
    with_ssas_connection do |olap|
      # Java expected [Employees].[Sheri Nowmer].[Michael Spence] but with
      # SsasCompatibleNaming the hierarchy displays [Employees].[Michael Spence].
      # The Java test never actually ran this assertion (it returned early when
      # SsasCompatibleNaming was false, the default).
      assert_query_returns olap, HR_MDX % "{[Employees].&[4]}",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Org Salary]}
          {[Measures].[Count]}
          Axis #2:
          {[Employees].[Michael Spence]}
          Row #0:
          Row #0:
        RESULT
    end
  end

  # Java: IndexedValuesTest#testQueryWithIndex
  # "level.&key" syntax — skipped because SsasCompatibleNaming causes
  # [Product].[Product Name] to be parsed as dimension.hierarchy instead
  # of dimension.level. This was dead code in the Java suite (the test
  # returned early when SsasCompatibleNaming was false, which is the default).
  it "query using level.&key syntax" do
    skip "level.&key syntax not supported with SsasCompatibleNaming"
  end
end
