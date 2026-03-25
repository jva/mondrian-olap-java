# frozen_string_literal: true

require_relative "test_helper"

describe "Infrastructure" do
  describe "query helpers" do
    before(:all) do
      create_olap_connection
    end

    it "assert_query_returns compares formatted output" do
      assert_query_returns @olap,
        "SELECT {[Measures].[Unit Sales]} ON COLUMNS FROM [Sales]",
        <<~RESULT
          Axis #0:
          {}
          Axis #1:
          {[Measures].[Unit Sales]}
          Row #0: 266,773
        RESULT
    end

    it "assert_axis_returns compares member names" do
      assert_axis_returns @olap,
        "[Gender].Children",
        "[Gender].[F]\n[Gender].[M]"
    end

    it "assert_expression_returns evaluates scalar expressions" do
      assert_expression_returns @olap, "1 + 2", "3"
    end

    it "assert_query_raises catches errors" do
      assert_query_raises @olap,
        "SELECT {[Nonexistent].[Foo]} ON 0 FROM [Sales]",
        /exception while parsing query/i
    end
  end

  describe "SQL capture" do
    before(:all) do
      create_olap_connection
    end

    it "capture_sql returns executed SQL statements" do
      @olap.flush_schema_cache
      captured_queries = capture_sql do
        @olap.execute("SELECT {[Measures].[Unit Sales]} ON 0 FROM [Sales]")
      end
      refute_empty captured_queries
      assert captured_queries.any? { |s| s.downcase.include?("sales_fact") },
        "Expected SQL referencing sales_fact table"
    end
  end

  describe "schema modification" do
    it "connection_with_modified_cube adds a calculated member" do
      olap = connection_with_modified_cube("Sales",
        calculated_members: <<~XML
          <CalculatedMember name="Double Units" dimension="Measures">
            <Formula>[Measures].[Unit Sales] * 2</Formula>
          </CalculatedMember>
        XML
      )
      result = olap.execute(
        "SELECT {[Measures].[Double Units]} ON 0 FROM [Sales]"
      )
      value = result.values.flatten.first
      assert value > 0, "Expected positive value, got #{value}"
    ensure
      olap&.close
    end
  end

  describe "Mondrian properties" do
    it "with_properties temporarily changes a property" do
      original = mondrian_property(:EnableNativeTopCount).get

      with_properties(EnableNativeTopCount: !original) do
        assert_equal !original, mondrian_property(:EnableNativeTopCount).get
      end

      assert_equal original, mondrian_property(:EnableNativeTopCount).get
    end
  end
end
