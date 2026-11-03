# frozen_string_literal: true

require_relative "test_helper"

# BuiltinFunTable registers "+" also with two string arguments, as in the
# Microsoft MDX dialect, and with a string and a number argument, as in
# JavaScript. It shares its calc with "||". Both operators convert a member or
# a number operand to its plain decimal string, which depends neither on the
# Java type and scale that the JDBC driver returns nor on the binary
# representation error of a double, and skip a null operand.
describe "String concatenation" do
  before(:all) do
    create_olap_connection
  end

  after(:all) do
    @olap.close
  end

  it "should concatenate two strings with +" do
    assert_expression_returns @olap, %q("Unit" + " Sales"), "Unit Sales"
  end

  it "should concatenate three strings with +" do
    assert_expression_returns @olap, %q("Unit" + " " + "Sales"), "Unit Sales"
  end

  it "should concatenate a string and an integral measure value with +" do
    assert_expression_returns @olap, %q("Sales: " + [Measures].[Unit Sales]), "Sales: 266773"
  end

  it "should concatenate a string and a decimal measure value with +" do
    assert_expression_returns @olap, %q("Sales: " + [Measures].[Store Sales]), "Sales: 565238.13"
  end

  it "should round a double sum to its decimal digits" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Sum] AS '0.1 + 0.2'
      MEMBER [Measures].[_Expr] AS '"Sum: " + [Measures].[_Sum]'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    assert_equal "Sum: 0.3", @olap.execute(mdx).formatted_values.flatten.first
  end

  it "should concatenate a 16 digit integral double exactly" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Sum] AS '1000000000000000 + 1'
      MEMBER [Measures].[_Expr] AS '"Sum: " + [Measures].[_Sum]'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    assert_equal "Sum: 1000000000000001", @olap.execute(mdx).formatted_values.flatten.first
  end

  # A numeric literal is a BigDecimal. A product of doubles keeps a large whole number double.
  it "should concatenate a large integral double without binary digits" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Product] AS '1.234567e25 * 1.0'
      MEMBER [Measures].[_Expr] AS '"Product: " + [Measures].[_Product]'
      SELECT {[Measures].[_Expr]} ON 0
      FROM [Sales]
    MDX
    assert_equal "Product: 12345670000000000000000000", @olap.execute(mdx).formatted_values.flatten.first
  end

  it "should concatenate infinite and NaN measure values" do
    mdx = <<~MDX
      WITH MEMBER [Measures].[_Infinity] AS '1 / 0'
      MEMBER [Measures].[_NaN] AS '0 / 0'
      MEMBER [Measures].[_Infinity Expr] AS '"Ratio: " || [Measures].[_Infinity]'
      MEMBER [Measures].[_NaN Expr] AS '"Ratio: " + [Measures].[_NaN]'
      SELECT {[Measures].[_Infinity Expr], [Measures].[_NaN Expr]} ON 0
      FROM [Sales]
    MDX
    assert_equal ["Ratio: Infinity", "Ratio: NaN"], @olap.execute(mdx).formatted_values.flatten
  end

  it "should concatenate a string and a measure value with ||" do
    assert_expression_returns @olap, %q("Sales: " || [Measures].[Unit Sales]), "Sales: 266773"
  end

  it "should concatenate a string and a member name with +" do
    assert_expression_returns @olap, %q("Gender: " + [Gender].[F].Name), "Gender: F"
  end

  it "should skip an empty measure value" do
    assert_expression_returns @olap, %q("Sales: " + ([Measures].[Unit Sales], [Time].[1998])), "Sales: "
  end

  it "should add two numbers with +" do
    assert_expression_returns @olap, "1 + 2", "3"
  end

  it "should add two measures with +" do
    assert_expression_returns @olap, "[Measures].[Unit Sales] + [Measures].[Unit Sales]", "533,546"
  end

  it "should add two Value operands with +" do
    assert_expression_returns @olap, %q(CoalesceEmpty(1, "x") + CoalesceEmpty(2, "x")), "3"
  end

  it "should add a Value operand and NULL with +" do
    assert_expression_returns @olap, %q(CoalesceEmpty(1, "x") + NULL), "1"
  end

  it "should add NULL and NULL with +" do
    assert_expression_returns @olap, "NULL + NULL", ""
  end

  it "should concatenate a string and a Value operand with +" do
    assert_expression_returns @olap, %q("Value: " + CoalesceEmpty(1, "x")), "Value: 1"
  end

  # RolapNativeSql compiles a numeric Filter condition to SQL. A string + condition is evaluated in Java.
  it "should filter with a string + condition" do
    mdx = %q(SELECT Filter([Store].[Store City].Members, ("1" + "2") = "12") ON 0 FROM [Sales])
    assert_equal 24, @olap.execute(mdx).column_names.size
  end

  it "should filter with a string + measure value condition" do
    mdx = <<~MDX
      SELECT Filter([Store].[Store City].Members, ("Sales: " + [Measures].[Unit Sales]) = "Sales: 25663") ON 0
      FROM [Sales]
    MDX
    assert_equal ["Los Angeles"], @olap.execute(mdx).column_names
  end

  it "should concatenate a string and a number with +" do
    assert_expression_returns @olap, %q("Count: " + 1), "Count: 1"
  end

  it "should concatenate a number and a string with +" do
    assert_expression_returns @olap, %q(1.5 + " units"), "1.5 units"
  end

  it "should concatenate a string and a numeric expression with +" do
    assert_expression_returns @olap, %q("Double: " + [Measures].[Unit Sales] * 2), "Double: 533546"
  end

  it "should add numbers before a string with + from left to right" do
    assert_expression_returns @olap, %q(1 + 2 + " units"), "3 units"
  end

  # CoalesceEmpty with a string argument has the String type.
  it "should concatenate CoalesceEmpty with a string fallback and a number with +" do
    assert_expression_returns @olap, %q(CoalesceEmpty([Measures].[Unit Sales], "0") + 1), "2667731"
  end

  it "should add CoalesceEmpty with a numeric fallback and a number with +" do
    assert_expression_returns @olap, "CoalesceEmpty([Measures].[Unit Sales], 0) + 1", "266,774"
  end

  describe "with user-defined functions" do
    before(:all) do
      schema = define_schema do
        cube 'Sales' do
          table 'sales_fact_1997'
          measure 'Unit Sales', column: 'unit_sales', aggregator: 'sum'
        end
        user_defined_function 'FailingString' do
          ruby do
            returns :string
            def call
              raise "FailingString failed"
            end
          end
        end
        # A Ruby integer beyond the Long range is a BigInteger in Java.
        user_defined_function 'BigIntegerValue' do
          ruby do
            returns :numeric
            def call
              123456789012345678901234567890
            end
          end
        end
        user_defined_function 'FloatValue' do
          ruby do
            returns :numeric
            def call
              java.lang.Float.new(0.1)
            end
          end
        end
      end
      @udf_olap = Mondrian::OLAP::Connection.create(CONNECTION_PARAMS.except(:catalog).merge(schema: schema))
    end

    after(:all) do
      @udf_olap.close
    end

    %w(|| +).each do |operator|
      it "should show the function error with #{operator}" do
        mdx = <<~MDX
          WITH MEMBER [Measures].[_Expr] AS '"Text: " #{operator} FailingString()'
          SELECT {[Measures].[_Expr]} ON 0
          FROM [Sales]
        MDX
        assert_match(/\A#ERR: .*FailingString failed/, @udf_olap.execute(mdx).formatted_values.flatten.first)
      end
    end

    it "should concatenate a BigInteger value exactly" do
      mdx = <<~MDX
        WITH MEMBER [Measures].[_Value] AS 'BigIntegerValue()'
        MEMBER [Measures].[_Expr] AS '"Value: " + [Measures].[_Value]'
        SELECT {[Measures].[_Expr]} ON 0
        FROM [Sales]
      MDX
      assert_equal "Value: 123456789012345678901234567890", @udf_olap.execute(mdx).formatted_values.flatten.first
    end

    it "should concatenate a Float value in its decimal form" do
      mdx = <<~MDX
        WITH MEMBER [Measures].[_Value] AS 'FloatValue()'
        MEMBER [Measures].[_Expr] AS '"Value: " + [Measures].[_Value]'
        SELECT {[Measures].[_Expr]} ON 0
        FROM [Sales]
      MDX
      assert_equal "Value: 0.1", @udf_olap.execute(mdx).formatted_values.flatten.first
    end
  end
end
