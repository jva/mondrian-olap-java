# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Subclass that stubs isValidContext to return a controlled value,
# replacing Mockito's spy/doReturn pattern from the Java test.
class StubbedNativeTopCount < Java::MondrianRolap::RolapNativeTopCount
  def initialize(valid_context:)
    super()
    @valid_context = valid_context
  end

  # Override the package-private isValidContext method.
  def isValidContext(_evaluator)
    @valid_context
  end
end

# Java: mondrian/rolap/TopCountNativeEvaluatorTest.java
describe "TopCountNativeEvaluator" do
  private

  def find_method(object, method_name, param_types = [])
    cls = object.java_class rescue object.getClass
    while cls
      begin
        method = cls.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
        method.accessible = true
        return method
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end
    raise "Method #{method_name} not found"
  end

  # Calls the package-private createEvaluator method via reflection.
  def invoke_create_evaluator(native_top_count, evaluator, fun_def, args)
    class_loader = Java::MondrianRolap::RolapNativeTopCount.java_class.getClassLoader
    evaluator_class = java.lang.Class.forName("mondrian.rolap.RolapEvaluator", true, class_loader)
    fun_def_class = Java::MondrianOlap::FunDef.java_class
    exp_array_class = java.lang.Class.forName("[Lmondrian.olap.Exp;", true, class_loader)

    method = find_method(native_top_count, "createEvaluator",
      [evaluator_class, fun_def_class, exp_array_class])
    method.invoke(native_top_count, evaluator, fun_def, args)
  end

  # Creates a FunDef proxy that returns "TOPCOUNT" for getName().
  # Replaces Mockito's mock(FunDef.class).
  def create_fun_def_proxy
    handler = proc do |_proxy, method, _args|
      case method.getName
      when "getName"
        "TOPCOUNT"
      else
        nil
      end
    end

    java.lang.reflect.Proxy.newProxyInstance(
      Java::MondrianOlap::FunDef.java_class.getClassLoader,
      [Java::MondrianOlap::FunDef.java_class].to_java(java.lang.Class),
      handler
    )
  end

  # Java: TopCountNativeEvaluatorTest#testNonNative_WhenExplicitlyDisabled
  it "returns null when native top count is explicitly disabled" do
    with_properties(EnableNativeTopCount: false) do
      native_top_count = Java::MondrianRolap::RolapNativeTopCount.new
      result = invoke_create_evaluator(native_top_count, nil, nil, nil)
      assert_nil result,
        "Native evaluator should not be created when 'mondrian.native.topcount.enable' is 'false'"
    end
  end

  # Java: TopCountNativeEvaluatorTest#testNonNative_WhenContextIsInvalid
  it "returns null when evaluation context is invalid" do
    with_properties(EnableNativeTopCount: true) do
      native_top_count = StubbedNativeTopCount.new(valid_context: false)
      result = invoke_create_evaluator(native_top_count, nil, nil, nil)
      assert_nil result,
        "Native evaluator should not be created when evaluation context is invalid"
    end
  end

  # For now, prohibit native evaluation of the function if has two
  # parameters. According to the specification, this means the function
  # should behave similarly to HEAD function. However, native evaluation
  # joins data with the fact table and if there is no data there, then some
  # records are ignored, what is not correct.
  #
  # See http://jira.pentaho.com/browse/MONDRIAN-2394
  #
  # Java: TopCountNativeEvaluatorTest#testNonNative_WhenTwoParametersArePassed
  it "returns null when two parameters are passed" do
    with_properties(EnableNativeTopCount: true) do
      native_top_count = StubbedNativeTopCount.new(valid_context: true)

      # Build the arguments array: [DummyExp(EmptyType), Literal(BigDecimal.ONE)]
      dummy_exp = Java::MondrianCalc::DummyExp.new(Java::MondrianOlapType::EmptyType.new)
      literal = Java::MondrianOlap::Literal.create(java.math.BigDecimal::ONE)
      arguments = [dummy_exp, literal].to_java(Java::MondrianOlap::Exp)

      fun_def = create_fun_def_proxy

      result = invoke_create_evaluator(native_top_count, nil, fun_def, arguments)
      assert_nil result,
        "Native evaluator should not be created when two parameters are passed"
    end
  end
end
