# frozen_string_literal: true

module QueryHelper
  # Format a result using the same formatter Java tests use.
  def format_result(result)
    string_writer = Java::JavaIo::StringWriter.new
    print_writer = Java::JavaIo::PrintWriter.new(string_writer)
    Java::OrgOlap4jLayout::TraditionalCellSetFormatter.new.format(result.raw_cell_set, print_writer)
    print_writer.flush
    string_writer.toString
  end

  # Execute MDX and assert the formatted result matches expected.
  # Uses assert_like (whitespace-normalized comparison from test_helper.rb).
  def assert_query_returns(olap, mdx, expected)
    result = olap.execute(mdx)
    actual = format_result(result)
    assert_like expected, actual
  end

  # Execute an axis expression against a cube (default: Sales).
  # Asserts member full names match expected (one per line).
  def assert_axis_returns(olap, expression, expected, cube: "Sales")
    mdx = "SELECT {#{expression}} ON 0 FROM [#{cube}]"
    actual = olap.execute(mdx).column_full_names.join("\n")
    assert_equal expected.strip, actual.strip
  end

  # Evaluate a scalar expression against a cube.
  # Wraps it in WITH MEMBER + SELECT, asserts the formatted cell value.
  def assert_expression_returns(olap, expression, expected, cube: "Sales")
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Expr] AS '#{expression}'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [#{cube}]
    MDX
    actual = olap.execute(mdx).formatted_values.flatten.first
    assert_equal expected.strip, actual.to_s.strip
  end

  # Assert that executing MDX raises a Mondrian error matching the pattern.
  # Pattern can be a Regexp or a String (substring match).
  def assert_query_raises(olap, mdx, pattern)
    error = assert_raises(Mondrian::OLAP::Error) { olap.execute(mdx) }
    if pattern.is_a?(Regexp)
      assert_match pattern, error.message
    else
      assert error.message.include?(pattern), "Expected error containing '#{pattern}', got: #{error.message}"
    end
  end
end
