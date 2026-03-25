# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../../test_helper"

Excel = Java::MondrianOlapFunVba::Excel
Vba = Java::MondrianOlapFunVba::Vba

# Java: mondrian/olap/fun/vba/ExcelTest.java
describe "Excel worksheet functions" do
  SMALL = 1e-10

  # Java: ExcelTest#testAcos
  it "acos" do
    # Cos(0) = 1
    # Cos(60 degrees) = .5
    # Cos(90 degrees) = 0
    # Cos(180 degrees) = -1
    assert_equal 0.0, Excel.acos(1.0)
    assert_in_delta Math::PI / 3.0, Excel.acos(0.5), SMALL
    assert_equal Math::PI / 2.0, Excel.acos(0.0)
    assert_equal Math::PI, Excel.acos(-1.0)
  end

  # Java: ExcelTest#testAcosh
  it "acosh" do
    # acosh(1) = 0
    # acosh(2) ~= 1
    # acosh(4) ~= 2
    assert_equal 0.0, Excel.acosh(1.0)
    assert_in_delta 1.3169578969248166, Excel.acosh(2.0), SMALL
    assert_in_delta 2.0634370688955608, Excel.acosh(4.0), SMALL
  end

  # Java: ExcelTest#testAsinh
  it "asinh" do
    # asinh(0) = 0
    # asinh(1) ~= 1
    # asinh(10) ~= 3
    # asinh(-x) = -asinh(x)
    assert_equal 0.0, Excel.asinh(0.0)
    assert_in_delta 0.8813735870195429, Excel.asinh(1.0), SMALL
    assert_in_delta 2.99822295029797, Excel.asinh(10.0), SMALL
    assert_in_delta(-2.99822295029797, Excel.asinh(-10.0), SMALL)
  end

  # Java: ExcelTest#testAtan2
  it "atan2" do
    assert_equal Math.atan2(0, 10), Excel.atan2(0, 10)
    assert_equal Math.atan2(1, 0.8), Excel.atan2(1, 0.8)
    assert_equal Math.atan2(-5, 0), Excel.atan2(-5, 0)
  end

  # Java: ExcelTest#testAtanh
  it "atanh" do
    # atanh(0) = 0
    # atanh(1) = +inf
    # atanh(-x) = -atanh(x)
    assert_equal 0.0, Excel.atanh(0)
    assert_in_delta 0.0100003333533347, Excel.atanh(0.01), SMALL
    assert_in_delta 0.549306144334054, Excel.atanh(0.5), SMALL
    assert_in_delta 1.4722194895832, Excel.atanh(0.9), SMALL
    assert_in_delta 2.64665241236224, Excel.atanh(0.99), SMALL
    assert_in_delta 6.1030338227611125, Excel.atanh(0.99999), SMALL
    assert_in_delta(-6.1030338227611125, Excel.atanh(-0.99999), SMALL)
  end

  # Java: ExcelTest#testCosh
  it "cosh" do
    assert_equal Math.cosh(0), Excel.cosh(0)
  end

  # Java: ExcelTest#testDegrees
  it "degrees" do
    assert_equal 90.0, Excel.degrees(Math::PI / 2)
  end

  # Java: ExcelTest#testLog10
  it "log10" do
    assert_equal 1.0, Excel.log10(10)
    assert_in_delta(-2.0, Excel.log10(0.01), 0.00000000000001)
  end

  # Java: ExcelTest#testPi
  it "pi" do
    assert_equal Math::PI, Excel.pi
  end

  # Java: ExcelTest#testPower
  it "power" do
    assert_equal 0.0, Excel.power(0, 5)
    assert_equal 1.0, Excel.power(5, 0)
    assert_equal 2.0, Excel.power(4, 0.5)
    assert_equal 0.125, Excel.power(2, -3)
  end

  # Java: ExcelTest#testRadians
  it "radians" do
    assert_equal Math::PI, Excel.radians(180.0)
    assert_equal(-Math::PI * 3.0, Excel.radians(-540.0))
  end

  # Java: ExcelTest#testSinh
  it "sinh" do
    assert_equal Math.sinh(0), Excel.sinh(0)
  end

  # Java: ExcelTest#testSqrtPi
  it "sqrtPi" do
    # sqrt(2 pi) = sqrt(6.28) ~ 2.5
    assert_in_delta 2.506628274631, Excel.sqrtPi(2.0), SMALL
  end

  # Java: ExcelTest#testTanh
  it "tanh" do
    assert_equal Math.tanh(0), Excel.tanh(0)
    assert_equal Math.tanh(0.44), Excel.tanh(0.44)
  end

  # Java: ExcelTest#testMod
  it "mod" do
    assert_equal 2.0, Excel.mod(28, 13)
    assert_equal(-11.0, Excel.mod(28, -13))
  end

  # Java: ExcelTest#testIntNative
  it "intNative" do
    assert_equal 5, Vba.intNative(5.1)
    assert_equal 5, Vba.intNative(5.9)
    assert_equal(-6, Vba.intNative(-5.9))
    assert_equal 0, Vba.intNative(0.1)
    assert_equal 0, Vba.intNative(0)
  end
end
