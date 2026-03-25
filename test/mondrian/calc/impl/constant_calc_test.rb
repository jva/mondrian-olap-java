# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/calc/impl/ConstantCalcTest.java
describe "ConstantCalc" do
  # Java: ConstantCalcTest#testNullEvaluatesToConstantDoubleNull
  it "null evaluates to constant DoubleNull" do
    constant_calc = Java::MondrianCalcImpl::ConstantCalc.new(Java::MondrianOlapType::NullType.new, nil)
    assert_equal Java::MondrianOlapFun::FunUtil::DoubleNull, constant_calc.evaluateDouble(nil)
  end

  # Java: ConstantCalcTest#testNullEvaluatesToConstantIntegerNull
  it "null evaluates to constant IntegerNull" do
    constant_calc = Java::MondrianCalcImpl::ConstantCalc.new(Java::MondrianOlapType::NullType.new, nil)
    assert_equal Java::MondrianOlapFun::FunUtil::IntegerNull, constant_calc.evaluateInteger(nil)
  end
end
