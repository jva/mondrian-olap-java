# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Dialect proxy InvocationHandler that returns MYSQL for getDatabaseProduct.
# Defined at file level to avoid constant lookup issues.
class DialectHandler
  include java.lang.reflect.InvocationHandler

  def initialize(database_product)
    @database_product = database_product
  end

  def invoke(_proxy, method, _args)
    case method.getName
    when "getDatabaseProduct"
      @database_product
    when "hashCode"
      java.lang.Integer.new(0)
    when "equals"
      false
    when "toString"
      "MockDialect"
    end
  end
end

# Java: mondrian/rolap/NumberSqlCompilerTest.java
describe "NumberSqlCompiler" do
  before do
    # Create a Dialect proxy that returns MYSQL for getDatabaseProduct
    database_product = Java::MondrianSpi::Dialect::DatabaseProduct::MYSQL
    dialect_class = Java::MondrianSpi::Dialect.java_class
    handler = DialectHandler.new(database_product)
    dialect = java.lang.reflect.Proxy.newProxyInstance(
      dialect_class.getClassLoader,
      [dialect_class].to_java(java.lang.Class),
      handler
    )

    # Create a real SqlQuery with the mock dialect
    sql_query = Java::MondrianRolapSql::SqlQuery.new(dialect, false)

    # Create RolapNativeSql instance
    native_sql = Java::MondrianRolap::RolapNativeSql.new(sql_query, nil, nil, nil)

    # Use reflection to instantiate the package-private NumberSqlCompiler inner class
    class_loader = native_sql.getClass.getClassLoader
    inner_class = java.lang.Class.forName(
      "mondrian.rolap.RolapNativeSql$NumberSqlCompiler", true, class_loader
    )
    constructor = inner_class.getDeclaredConstructors.first
    constructor.setAccessible(true)
    # Non-static inner class has implicit first parameter for enclosing instance
    @compiler = constructor.newInstance(native_sql)
  end

  # Java: NumberSqlCompilerTest#testRejectsNonLiteral
  it "rejects non-literal expression" do
    expression = Java::MondrianCalc::DummyExp.new(Java::MondrianOlapType::NullType.new)
    assert_nil @compiler.compile(expression)
  end

  # Java: NumberSqlCompilerTest#testAcceptsNumeric
  it "accepts numeric literal" do
    expression = Java::MondrianOlap::Literal.create(java.math.BigDecimal::ONE)
    refute_nil @compiler.compile(expression)
  end

  # Java: NumberSqlCompilerTest#testAcceptsString_Int
  it "accepts string integer" do
    expression = Java::MondrianOlap::Literal.createString("1")
    refute_nil @compiler.compile(expression)
  end

  # Java: NumberSqlCompilerTest#testAcceptsString_Negative
  it "accepts string negative number" do
    expression = Java::MondrianOlap::Literal.createString("-1")
    refute_nil @compiler.compile(expression)
  end

  # Java: NumberSqlCompilerTest#testAcceptsString_ExplicitlyPositive
  it "accepts string explicitly positive number" do
    expression = Java::MondrianOlap::Literal.createString("+1.01")
    refute_nil @compiler.compile(expression)
  end

  # Java: NumberSqlCompilerTest#testAcceptsString_NoIntegerPart
  it "accepts string with no integer part" do
    expression = Java::MondrianOlap::Literal.createString("-.00001")
    refute_nil @compiler.compile(expression)
  end

  # Java: NumberSqlCompilerTest#testRejectsString_SelectStatement
  it "rejects string select statement" do
    expression = Java::MondrianOlap::Literal.createString("(select 100)")
    assert_raises(Java::MondrianOlapFun::MondrianEvaluationException) do
      @compiler.compile(expression)
    end
  end

  # Java: NumberSqlCompilerTest#testRejectsString_NaN
  it "rejects string NaN" do
    expression = Java::MondrianOlap::Literal.createString("NaN")
    assert_raises(Java::MondrianOlapFun::MondrianEvaluationException) do
      @compiler.compile(expression)
    end
  end

  # Java: NumberSqlCompilerTest#testRejectsString_Infinity
  it "rejects string Infinity" do
    expression = Java::MondrianOlap::Literal.createString("Infinity")
    assert_raises(Java::MondrianOlapFun::MondrianEvaluationException) do
      @compiler.compile(expression)
    end
  end

  # Java: NumberSqlCompilerTest#testRejectsString_TwoDots
  it "rejects string with two dots" do
    expression = Java::MondrianOlap::Literal.createString("1.0.")
    assert_raises(Java::MondrianOlapFun::MondrianEvaluationException) do
      @compiler.compile(expression)
    end
  end

  # Java: NumberSqlCompilerTest#testRejectsString_OnlyDot
  it "rejects string with only a dot" do
    expression = Java::MondrianOlap::Literal.createString(".")
    assert_raises(Java::MondrianOlapFun::MondrianEvaluationException) do
      @compiler.compile(expression)
    end
  end

  # Java: NumberSqlCompilerTest#testRejectsString_DoubleNegation
  it "rejects string with double negation" do
    expression = Java::MondrianOlap::Literal.createString("--1.0")
    assert_raises(Java::MondrianOlapFun::MondrianEvaluationException) do
      @compiler.compile(expression)
    end
  end
end
