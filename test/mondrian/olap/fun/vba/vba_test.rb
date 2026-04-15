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

Vba = Java::MondrianOlapFunVba::Vba
InvalidArgumentException = Java::MondrianOlap::InvalidArgumentException

# Java: mondrian/olap/fun/vba/VbaTest.java
describe "VBA functions" do
  SMALL = 1e-10

  DateFormat = java.text.DateFormat
  SimpleDateFormat = java.text.SimpleDateFormat
  Calendar = java.util.Calendar
  Locale = java.util.Locale

  def sample_date
    calendar = Calendar.getInstance
    # Thursday 2008-04-24 7:10:45pm
    # Chose a Thursday because 2008 starts on a Tuesday - it makes weeks interesting.
    calendar.set(2008, 3, 24, 19, 10, 45) # month is 0-based
    calendar.getTime
  end

  def to_date(date_string)
    pattern = date_string.include?(":") ? "yyyy/MM/dd HH:mm:ss" : "yyyy/MM/dd"
    date_format = SimpleDateFormat.new(pattern, Locale::US)
    date_format.parse(date_string)
  end

  def format_date(date)
    date_format = SimpleDateFormat.new("yyyy/MM/dd HH:mm:ss", Locale::US)
    date_format.format(date)
  end

  def assert_date_equal(expected_string, date)
    assert_equal expected_string, format_date(date)
  end

  def assert_message(exception, expected)
    message = "#{exception.java_class.name}: #{exception.message}"
    assert_includes message, expected,
      "expected message to contain '#{expected}', got '#{message}'"
  end

  def time_zone_name
    java.util.TimeZone.getDefault.getDisplayName
  end

  def pst?
    time_zone_name == "America/Los_Angeles" || time_zone_name == "Pacific Standard Time"
  end

  # Conversion functions

  # Java: VbaTest#testCBool
  it "cBool" do
    assert_equal true, Vba.cBool(java.lang.Boolean::TRUE)
    assert_equal false, Vba.cBool(java.lang.Boolean::FALSE)
    assert_equal true, Vba.cBool(1.5)
    assert_equal true, Vba.cBool("1.5")
    assert_equal false, Vba.cBool("0.00")
    error = assert_raises(java.lang.RuntimeException) { Vba.cBool("a") }
    assert_message error, "NumberFormatException"
    # Per the spec, the string "true" is no different from any other
    error = assert_raises(java.lang.RuntimeException) { Vba.cBool("true") }
    assert_message error, "NumberFormatException"
  end

  # Java: VbaTest#testCInt
  it "cInt" do
    assert_equal 1, Vba.cInt(1)
    assert_equal 1, Vba.cInt(1.4)
    # CInt rounds to the nearest even number
    assert_equal 2, Vba.cInt(1.5)
    assert_equal 2, Vba.cInt(2.5)
    assert_equal 2, Vba.cInt(1.6)
    assert_equal(-1, Vba.cInt(-1.4))
    assert_equal(-2, Vba.cInt(-1.5))
    assert_equal(-2, Vba.cInt(-1.6))
    assert_equal java.lang.Integer::MAX_VALUE, Vba.cInt(java.lang.Integer::MAX_VALUE.to_f)
    assert_equal java.lang.Integer::MIN_VALUE, Vba.cInt(java.lang.Integer::MIN_VALUE.to_f)
    assert_equal java.lang.Short::MAX_VALUE, Vba.cInt(java.lang.Short::MAX_VALUE.to_f + 0.4)
    assert_equal java.lang.Short::MIN_VALUE, Vba.cInt(java.lang.Short::MIN_VALUE.to_f + 0.4)
    error = assert_raises(java.lang.RuntimeException) { Vba.cInt("a") }
    assert_message error, "NumberFormatException"
  end

  # Java: VbaTest#testInt
  it "int_" do
    # if negative, Int() returns the closest number less than or
    # equal to the number.
    assert_equal 1, Vba.int_(1)
    assert_equal 1, Vba.int_(1.4)
    assert_equal 1, Vba.int_(1.5)
    assert_equal 2, Vba.int_(2.5)
    assert_equal 1, Vba.int_(1.6)
    assert_equal(-2, Vba.int_(-2))
    assert_equal(-2, Vba.int_(-1.4))
    assert_equal(-2, Vba.int_(-1.5))
    assert_equal(-2, Vba.int_(-1.6))
    assert_equal java.lang.Integer::MAX_VALUE, Vba.int_(java.lang.Integer::MAX_VALUE.to_f)
    assert_equal java.lang.Integer::MIN_VALUE, Vba.int_(java.lang.Integer::MIN_VALUE.to_f)
    error = assert_raises(java.lang.RuntimeException) { Vba.int_("a") }
    assert_message error, "Invalid parameter."
  end

  # Java: VbaTest#testFix
  it "fix" do
    # if negative, Fix() returns the closest number greater than or
    # equal to the number.
    assert_equal 1, Vba.fix(1)
    assert_equal 1, Vba.fix(1.4)
    assert_equal 1, Vba.fix(1.5)
    assert_equal 2, Vba.fix(2.5)
    assert_equal 1, Vba.fix(1.6)
    assert_equal(-1, Vba.fix(-1))
    assert_equal(-1, Vba.fix(-1.4))
    assert_equal(-1, Vba.fix(-1.5))
    assert_equal(-1, Vba.fix(-1.6))
    assert_equal java.lang.Integer::MAX_VALUE, Vba.fix(java.lang.Integer::MAX_VALUE.to_f)
    assert_equal java.lang.Integer::MIN_VALUE, Vba.fix(java.lang.Integer::MIN_VALUE.to_f)
    error = assert_raises(java.lang.RuntimeException) { Vba.fix("a") }
    assert_message error, "Invalid parameter."
  end

  # Java: VbaTest#testCDbl
  it "cDbl" do
    assert_equal 1.0, Vba.cDbl(1)
    assert_equal 1.4, Vba.cDbl(1.4)
    assert_equal 1.5, Vba.cDbl(1.5)
    assert_equal 2.5, Vba.cDbl(2.5)
    assert_equal 1.6, Vba.cDbl(1.6)
    assert_equal(-1.4, Vba.cDbl(-1.4))
    assert_equal(-1.5, Vba.cDbl(-1.5))
    assert_equal(-1.6, Vba.cDbl(-1.6))
    assert_equal(-1.6, Vba.cDbl("-1.6"))
    assert_equal java.lang.Double::MAX_VALUE, Vba.cDbl(java.lang.Double::MAX_VALUE)
    assert_equal java.lang.Double::MIN_VALUE, Vba.cDbl(java.lang.Double::MIN_VALUE)
    error = assert_raises(java.lang.RuntimeException) { Vba.cDbl("a") }
    assert_message error, "NumberFormatException"
  end

  # Java: VbaTest#testHex
  it "hex" do
    assert_equal "0", Vba.hex(0)
    assert_equal "1", Vba.hex(1)
    assert_equal "A", Vba.hex(10)
    assert_equal "64", Vba.hex(100)
    assert_equal "FFFFFFFF", Vba.hex(-1)
    assert_equal "FFFFFFF6", Vba.hex(-10)
    assert_equal "FFFFFF9C", Vba.hex(-100)
    error = assert_raises(java.lang.RuntimeException) { Vba.hex("a") }
    assert_message error, "Invalid parameter."
  end

  # Java: VbaTest#testOct
  it "oct" do
    assert_equal "0", Vba.oct(0)
    assert_equal "1", Vba.oct(1)
    assert_equal "12", Vba.oct(10)
    assert_equal "144", Vba.oct(100)
    assert_equal "37777777777", Vba.oct(-1)
    assert_equal "37777777766", Vba.oct(-10)
    assert_equal "37777777634", Vba.oct(-100)
    error = assert_raises(java.lang.RuntimeException) { Vba.oct("a") }
    assert_message error, "Invalid parameter."
  end

  # Java: VbaTest#testStr
  it "str" do
    assert_equal " 0", Vba.str(0)
    assert_equal " 1", Vba.str(1)
    assert_equal " 10", Vba.str(10)
    assert_equal " 100", Vba.str(100)
    assert_equal "-1", Vba.str(-1)
    assert_equal "-10", Vba.str(-10)
    assert_equal "-100", Vba.str(-100)
    assert_equal "-10.123", Vba.str(-10.123)
    assert_equal " 10.123", Vba.str(10.123)
    error = assert_raises(java.lang.RuntimeException) { Vba.oct("a") }
    assert_message error, "Invalid parameter."
  end

  # Java: VbaTest#testVal
  it "val" do
    assert_equal(-1615198.0, Vba.val(" -  1615 198th Street N.E."))
    assert_equal 1615198.0, Vba.val(" 1615 198th Street N.E.")
    assert_equal 1615.198, Vba.val(" 1615 . 198th Street N.E.")
    assert_equal 1615.19, Vba.val(" 1615 . 19 . 8th Street N.E.")
    assert_equal 0xffff.to_f, Vba.val("&HFFFF")
    assert_equal 668.0, Vba.val("&O1234")
  end

  # Java: VbaTest#testCDate
  it "cDate" do
    date = java.util.Date.new
    assert_equal date, Vba.cDate(date)
    assert_nil Vba.cDate(nil)

    # cDate internally uses DateFormat.getTimeInstance, getDateTimeInstance, getDateInstance
    # in that order. The expected results must use the same parsing chain so the test is
    # JDK-version independent (DateFormat formats changed between Java 8 and Java 11+).
    assert_equal(
      DateFormat.getDateInstance.parse("Jan 12, 1952"),
      Vba.cDate("Jan 12, 1952"))
    assert_equal(
      DateFormat.getDateInstance.parse("October 19, 1962"),
      Vba.cDate("October 19, 1962"))
    assert_equal(
      DateFormat.getTimeInstance.parse("4:35:47 PM"),
      Vba.cDate("4:35:47 PM"))
    # "October 19, 1962 4:35:47 PM" - cDate tries time, then datetime, then date.
    # On Java 11+ the datetime parser may not match this format, so cDate falls back to
    # the date-only parser. Use the same fallback chain for the expected value.
    expected = begin
      DateFormat.getDateTimeInstance.parse("October 19, 1962 4:35:47 PM")
    rescue java.text.ParseException
      DateFormat.getDateInstance.parse("October 19, 1962 4:35:47 PM")
    end
    assert_equal expected, Vba.cDate("October 19, 1962 4:35:47 PM")

    error = assert_raises(InvalidArgumentException) { Vba.cDate("Jan, 1952") }
    assert_includes error.message, "Jan, 1952"
  end

  # Java: VbaTest#testIsDate
  it "isDate" do
    assert_equal false, Vba.isDate(nil)
    assert_equal true, Vba.isDate(java.util.Date.new)
    assert_equal true, Vba.isDate("Jan 12, 1952")
    assert_equal true, Vba.isDate("October 19, 1962")
    assert_equal true, Vba.isDate("4:35:47 PM")
    assert_equal true, Vba.isDate("October 19, 1962 4:35:47 PM")
    assert_equal false, Vba.isDate("Jan, 1952")
  end

  # DateTime

  # Java: VbaTest#testDateAdd
  it "dateAdd" do
    sample = sample_date
    assert_date_equal "2008/04/24 19:10:45", sample

    calendar = Calendar.getInstance
    calendar.set(2007, 1, 1, 0, 0, 0) # 0-based month
    feb2007 = calendar.getTime
    assert_date_equal "2007/02/01 00:00:00", feb2007

    assert_date_equal "2008/04/24 19:10:45", Vba.dateAdd("yyyy", 0, sample)
    assert_date_equal "2009/04/24 19:10:45", Vba.dateAdd("yyyy", 1, sample)
    assert_date_equal "2006/04/24 19:10:45", Vba.dateAdd("yyyy", -2, sample)

    # partial years interpolate - only test in PST timezone
    if pst?
      sample_plus_two_point_five_years = Vba.dateAdd("yyyy", 2.5, sample)
      date_string = format_date(sample_plus_two_point_five_years)
      assert(
        date_string == "2010/10/24 06:40:45" || date_string == "2010/10/24 07:10:45",
        "Got #{date_string}")
    end

    assert_date_equal "2009/01/24 19:10:45", Vba.dateAdd("q", 3, sample)

    # partial months are interesting!
    assert_date_equal "2008/06/24 19:10:45", Vba.dateAdd("m", 2, sample)
    assert_date_equal "2007/01/01 00:00:00", Vba.dateAdd("m", -1, feb2007)
    assert_date_equal "2007/03/01 00:00:00", Vba.dateAdd("m", 1, feb2007)
    assert_date_equal "2007/02/08 00:00:00", Vba.dateAdd("m", 0.25, feb2007)
    # feb 2008 is a leap month, so a quarter month is 7.25 days
    assert_date_equal "2008/02/08 06:00:00", Vba.dateAdd("m", 12.25, feb2007)

    assert_date_equal "2008/05/01 19:10:45", Vba.dateAdd("y", 7, sample)
    assert_date_equal "2008/05/02 01:10:45", Vba.dateAdd("y", 7.25, sample)
    assert_date_equal "2008/04/24 23:10:45", Vba.dateAdd("h", 4, sample)
    assert_date_equal "2008/04/24 20:00:45", Vba.dateAdd("n", 50, sample)
    assert_date_equal "2008/04/24 19:10:36", Vba.dateAdd("s", -9, sample)
  end

  # Java: VbaTest#testAddDate_Days_NextYear
  it "addDate days next year" do
    dec31 = to_date("2001/12/31")
    %w(y d).each do |i|
      assert_date_equal "2002/01/01 00:00:00", Vba.dateAdd(i, 1, dec31)
    end
  end

  # Java: VbaTest#testAddDate_Days_PreviousMonth
  it "addDate days previous month" do
    dec31 = to_date("2001/12/31")
    %w(y d).each do |i|
      assert_date_equal "2001/11/30 00:00:00", Vba.dateAdd(i, -31, dec31)
    end
  end

  # Java: VbaTest#testAddDate_Days_NextMonth
  it "addDate days next month" do
    jan1 = to_date("2001/01/01")
    %w(y d).each do |i|
      assert_date_equal "2001/02/01 00:00:00", Vba.dateAdd(i, 31, jan1)
    end
  end

  # Java: VbaTest#testAddDate_Days_PreviousYear
  it "addDate days previous year" do
    jan1 = to_date("2001/01/01")
    %w(y d).each do |i|
      assert_date_equal "2000/12/31 00:00:00", Vba.dateAdd(i, -1, jan1)
    end
  end

  # Java: VbaTest#testAddDate_Days_LeapYear
  it "addDate days leap year" do
    feb28 = to_date("2012/02/28")
    mar1 = to_date("2012/03/01")
    %w(y d).each do |i|
      assert_date_equal "2012/02/29 00:00:00", Vba.dateAdd(i, 1, feb28)
      assert_date_equal "2012/02/29 00:00:00", Vba.dateAdd(i, -1, mar1)
    end
  end

  # Java: VbaTest#testDateDiff
  it "dateDiff" do
    # TODO: empty in the Java source
  end

  # Java: VbaTest#testDateDiff_Days_SameDay
  it "dateDiff days same day" do
    date = to_date("2000/01/01 00:00:00")
    last_second = to_date("2000/01/01 23:59:59")
    %w(y d).each do |i|
      assert_equal 0, Vba.dateDiff(i, date, date), i
      assert_equal 0, Vba.dateDiff(i, date, last_second), i
      assert_equal 0, Vba.dateDiff(i, last_second, date), i
    end
  end

  # Java: VbaTest#testDateDiff_Days_LessThanOneDaySameYear
  it "dateDiff days less than one day same year" do
    date = to_date("2001/01/01 05:00:00")
    next_day = to_date("2001/01/02 00:00:00")
    %w(y d).each do |i|
      assert_equal 0, Vba.dateDiff(i, date, next_day), i
      assert_equal 0, Vba.dateDiff(i, next_day, date), i
    end
  end

  # Java: VbaTest#testDateDiff_Days_LessThanOneDaySpanYear
  it "dateDiff days less than one day span year" do
    date = to_date("2001/12/31 05:00:00")
    next_month = to_date("2002/01/01 00:00:00")
    %w(y d).each do |i|
      assert_equal 0, Vba.dateDiff(i, date, next_month), i
      assert_equal 0, Vba.dateDiff(i, next_month, date), i
    end
  end

  # Java: VbaTest#testDateDiff_Days_24hours
  it "dateDiff days 24 hours" do
    date = to_date("2001/01/01 05:00:00")
    after24hours = to_date("2001/01/02 05:00:00")
    %w(y d).each do |i|
      assert_equal 1, Vba.dateDiff(i, date, after24hours), i
      assert_equal(-1, Vba.dateDiff(i, after24hours, date), i)
    end
  end

  # Java: VbaTest#testDateDiff_Days_DST
  it "dateDiff days DST" do
    dst_in_2015 = to_date("2015/03/08 00:00:00")
    next_day = to_date("2015/03/09 00:00:00")
    %w(y d).each do |i|
      assert_equal 1, Vba.dateDiff(i, dst_in_2015, next_day), i
      assert_equal(-1, Vba.dateDiff(i, next_day, dst_in_2015), i)
    end
  end

  # Java: VbaTest#testDateDiff_Days_NextDay
  it "dateDiff days next day" do
    date = to_date("2001/01/01 00:00:00")
    next_day = to_date("2001/01/02 00:00:00")
    %w(y d).each do |i|
      assert_equal 1, Vba.dateDiff(i, date, next_day), i
      assert_equal(-1, Vba.dateDiff(i, next_day, date), i)
    end
  end

  # Java: VbaTest#testDateDiff_Days_NextMonth
  it "dateDiff days next month" do
    date = to_date("2001/01/01 00:00:00")
    next_month = to_date("2001/02/01 00:00:00")
    %w(y d).each do |i|
      assert_equal 31, Vba.dateDiff(i, date, next_month), i
      assert_equal(-31, Vba.dateDiff(i, next_month, date), i)
    end
  end

  # Java: VbaTest#testDateDiff_Days_NextYear
  it "dateDiff days next year" do
    date = to_date("2001/01/01 00:00:00")
    next_year = to_date("2002/01/01 00:00:00")
    %w(y d).each do |i|
      assert_equal 365, Vba.dateDiff(i, date, next_year), i
      assert_equal(-365, Vba.dateDiff(i, next_year, date), i)
    end
  end

  # Java: VbaTest#testDateDiff_Days_FromDecToJan
  it "dateDiff days from Dec to Jan" do
    date = to_date("2001/12/01 00:00:00")
    next_month = to_date("2002/01/01 00:00:00")
    %w(y d).each do |i|
      assert_equal 31, Vba.dateDiff(i, date, next_month), i
      assert_equal(-31, Vba.dateDiff(i, next_month, date), i)
    end
  end

  # Java: VbaTest#testDatePart2
  it "datePart with 2 args" do
    sample = sample_date
    assert_equal 2008, Vba.datePart("yyyy", sample)
    assert_equal 2, Vba.datePart("q", sample)  # 2nd quarter
    assert_equal 4, Vba.datePart("m", sample)
    assert_equal 5, Vba.datePart("w", sample)  # thursday
    assert_equal 17, Vba.datePart("ww", sample)
    assert_equal 115, Vba.datePart("y", sample)
    assert_equal 19, Vba.datePart("h", sample)
    assert_equal 10, Vba.datePart("n", sample)
    assert_equal 45, Vba.datePart("s", sample)
  end

  # Java: VbaTest#testDatePart3
  it "datePart with 3 args" do
    sample = sample_date
    assert_equal 5, Vba.datePart("w", sample, Calendar::SUNDAY)
    assert_equal 4, Vba.datePart("w", sample, Calendar::MONDAY)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::SUNDAY)
    assert_equal 18, Vba.datePart("ww", sample, Calendar::WEDNESDAY)
    assert_equal 18, Vba.datePart("ww", sample, Calendar::THURSDAY)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::FRIDAY)
  end

  # Java: VbaTest#testDatePart4
  it "datePart with 4 args" do
    sample = sample_date
    # 2008 starts on a Tuesday
    # 2008-04-29 is a Thursday
    # That puts it in week 17 by most ways of computing weeks
    assert_equal 17, Vba.datePart("ww", sample, Calendar::SUNDAY, 0)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::SUNDAY, 1)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::SUNDAY, 2)
    assert_equal 16, Vba.datePart("ww", sample, Calendar::SUNDAY, 3)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::MONDAY, 0)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::MONDAY, 1)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::MONDAY, 2)
    assert_equal 16, Vba.datePart("ww", sample, Calendar::MONDAY, 3)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::TUESDAY, 0)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::TUESDAY, 1)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::TUESDAY, 2)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::TUESDAY, 3)
    assert_equal 18, Vba.datePart("ww", sample, Calendar::WEDNESDAY, 0)
    assert_equal 18, Vba.datePart("ww", sample, Calendar::WEDNESDAY, 1)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::WEDNESDAY, 2)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::WEDNESDAY, 3)
    assert_equal 18, Vba.datePart("ww", sample, Calendar::THURSDAY, 0)
    assert_equal 18, Vba.datePart("ww", sample, Calendar::THURSDAY, 1)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::THURSDAY, 2)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::THURSDAY, 3)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::FRIDAY, 0)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::FRIDAY, 1)
    assert_equal 16, Vba.datePart("ww", sample, Calendar::FRIDAY, 2)
    assert_equal 16, Vba.datePart("ww", sample, Calendar::FRIDAY, 3)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::SATURDAY, 0)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::SATURDAY, 1)
    assert_equal 17, Vba.datePart("ww", sample, Calendar::SATURDAY, 2)
    assert_equal 16, Vba.datePart("ww", sample, Calendar::SATURDAY, 3)

    error = assert_raises(java.lang.RuntimeException) do
      Vba.datePart("ww", sample, Calendar::SUNDAY, 4)
    end
    assert_message error, "ArrayIndexOutOfBoundsException"
  end

  # Java: VbaTest#testDatePart_Y_vs_D
  it "datePart y vs d" do
    dec1 = to_date("2001/12/01")
    assert_equal 335, Vba.datePart("y", dec1)
    assert_equal 1, Vba.datePart("d", dec1)
  end

  # Java: VbaTest#testDate
  it "date" do
    date = Vba.date
    refute_nil date
    calendar = Calendar.getInstance
    calendar.setTime(date)
    assert_equal 0, calendar.get(Calendar::HOUR_OF_DAY)
    assert_equal 0, calendar.get(Calendar::MILLISECOND)
  end

  # Java: VbaTest#testDateSerial
  it "dateSerial" do
    date = Vba.dateSerial(2008, 2, 1)
    assert_date_equal "2008/02/01 00:00:00", date
  end

  # Java: VbaTest#testFormatDateTime
  it "formatDateTime" do
    # Use SimpleDateFormat to create the date in a JDK-version-independent way
    sdf = SimpleDateFormat.new("MMMM dd, yyyy h:mm:ss a", Locale::US)
    date = sdf.parse("October 19, 1962 4:35:47 PM")
    # The default format output depends on JDK version (Java 11+ adds comma after year)
    expected_default = DateFormat.getDateTimeInstance.format(date)
    assert_equal expected_default, Vba.formatDateTime(date)
    assert_equal expected_default, Vba.formatDateTime(date, 0)
    expected_long = DateFormat.getDateInstance(DateFormat::LONG).format(date)
    assert_equal expected_long, Vba.formatDateTime(date, 1)
    expected_short = DateFormat.getDateInstance(DateFormat::SHORT).format(date)
    assert_equal expected_short, Vba.formatDateTime(date, 2)
    datestr = Vba.formatDateTime(date, 3)
    refute_nil datestr
    # skip the timezone so this test runs everywhere
    assert datestr.start_with?("4:35:47 PM"), "Expected to start with '4:35:47 PM', got '#{datestr}'"
    expected_short_time = DateFormat.getTimeInstance(DateFormat::SHORT).format(date)
    assert_equal expected_short_time, Vba.formatDateTime(date, 4)
  end

  # Java: VbaTest#testDateValue
  it "dateValue" do
    date = java.util.Date.new
    date1 = Vba.dateValue(date)
    calendar = Calendar.getInstance
    calendar.setTime(date1)
    assert_equal 0, calendar.get(Calendar::HOUR_OF_DAY)
    assert_equal 0, calendar.get(Calendar::MINUTE)
    assert_equal 0, calendar.get(Calendar::SECOND)
    assert_equal 0, calendar.get(Calendar::MILLISECOND)
  end

  # Java: VbaTest#testDay
  it "day" do
    assert_equal 24, Vba.day(sample_date)
  end

  # Java: VbaTest#testHour
  it "hour" do
    assert_equal 19, Vba.hour(sample_date)
  end

  # Java: VbaTest#testMinute
  it "minute" do
    assert_equal 10, Vba.minute(sample_date)
  end

  # Java: VbaTest#testMonth
  it "month" do
    assert_equal 4, Vba.month(sample_date)
  end

  # Java: VbaTest#testNow
  it "now" do
    date = Vba.now
    refute_nil date
  end

  # Java: VbaTest#testSecond
  it "second" do
    assert_equal 45, Vba.second(sample_date)
  end

  # Java: VbaTest#testTimeSerial
  it "timeSerial" do
    date = Vba.timeSerial(17, 42, 10)
    assert_date_equal "1970/01/01 17:42:10", date
  end

  # Java: VbaTest#testTimeValue
  it "timeValue" do
    assert_date_equal "1970/01/01 19:10:45", Vba.timeValue(sample_date)
  end

  # Java: VbaTest#testTimer
  it "timer" do
    v = Vba.timer
    assert v >= 0
    assert v < 24 * 60 * 60
  end

  # Java: VbaTest#testWeekday1
  it "weekday with 1 arg" do
    if Calendar.getInstance.getFirstDayOfWeek == Calendar::SUNDAY
      assert_equal Calendar::THURSDAY, Vba.weekday(sample_date)
    end
  end

  # Java: VbaTest#testWeekday2
  it "weekday with 2 args" do
    sample = sample_date
    # 2008/4/24 falls on a Thursday.

    # If Sunday is the first day of the week, Thursday is day 5.
    assert_equal 5, Vba.weekday(sample, Calendar::SUNDAY)

    # If Monday is the first day of the week, then 2008/4/24 falls on the
    # 4th day of the week
    assert_equal 4, Vba.weekday(sample, Calendar::MONDAY)

    assert_equal 3, Vba.weekday(sample, Calendar::TUESDAY)
    assert_equal 2, Vba.weekday(sample, Calendar::WEDNESDAY)
    assert_equal 1, Vba.weekday(sample, Calendar::THURSDAY)
    assert_equal 7, Vba.weekday(sample, Calendar::FRIDAY)
    assert_equal 6, Vba.weekday(sample, Calendar::SATURDAY)
  end

  # Java: VbaTest#testYear
  it "year" do
    assert_equal 2008, Vba.year(sample_date)
  end

  # Java: VbaTest#testFormatNumber
  it "formatNumber" do
    assert_equal "1", Vba.formatNumber(1.0)
    assert_equal "1.0", Vba.formatNumber(1.0, 1)

    assert_equal "0.1", Vba.formatNumber(0.1, -1, -1)
    assert_equal ".1", Vba.formatNumber(0.1, -1, 0)
    assert_equal "0.1", Vba.formatNumber(0.1, -1, 1)

    assert_equal "-1", Vba.formatNumber(-1, -1, 1, -1)
    assert_equal "-1", Vba.formatNumber(-1, -1, 1, 0)
    assert_equal "(1)", Vba.formatNumber(-1, -1, 1, 1)

    assert_equal "1", Vba.formatNumber(1, -1, 1, -1)
    assert_equal "1", Vba.formatNumber(1, -1, 1, 0)
    assert_equal "1", Vba.formatNumber(1, -1, 1, 1)

    assert_equal "1,000", Vba.formatNumber(1000.0, -1, -1, -1, -1)
    assert_equal "1000.0", Vba.formatNumber(1000.0, 1, -1, -1, 0)
    assert_equal "1,000.0", Vba.formatNumber(1000.0, 1, -1, -1, 1)
  end

  # Java: VbaTest#testFormatPercent
  it "formatPercent" do
    assert_equal "100%", Vba.formatPercent(1.0)
    assert_equal "100.0%", Vba.formatPercent(1.0, 1)

    assert_equal "0.1%", Vba.formatPercent(0.001, 1, -1)
    assert_equal ".1%", Vba.formatPercent(0.001, 1, 0)
    assert_equal "0.1%", Vba.formatPercent(0.001, 1, 1)

    assert_equal "11%", Vba.formatPercent(0.111, -1)
    assert_equal "11%", Vba.formatPercent(0.111, 0)
    assert_equal "11.100%", Vba.formatPercent(0.111, 3)

    assert_equal "-100%", Vba.formatPercent(-1, -1, 1, -1)
    assert_equal "-100%", Vba.formatPercent(-1, -1, 1, 0)
    assert_equal "(100%)", Vba.formatPercent(-1, -1, 1, 1)

    assert_equal "100%", Vba.formatPercent(1, -1, 1, -1)
    assert_equal "100%", Vba.formatPercent(1, -1, 1, 0)
    assert_equal "100%", Vba.formatPercent(1, -1, 1, 1)

    assert_equal "100,000%", Vba.formatPercent(1000.0, -1, -1, -1, -1)
    assert_equal "100000.0%", Vba.formatPercent(1000.0, 1, -1, -1, 0)
    assert_equal "100,000.0%", Vba.formatPercent(1000.0, 1, -1, -1, 1)
  end

  # Java: VbaTest#testFormatCurrency
  it "formatCurrency" do
    # formatCurrency uses NumberFormat.getCurrencyInstance() which is locale-dependent.
    # Build expected strings using the same formatter to be locale-independent.
    fmt = java.text.NumberFormat.getCurrencyInstance
    cs = fmt.getCurrency.getSymbol

    assert_equal "#{cs}1.00", Vba.formatCurrency(1.0)
    assert_equal "#{cs}0.00", Vba.formatCurrency(0.0)
    assert_equal "#{cs}1.0", Vba.formatCurrency(1.0, 1)
    assert_equal "#{cs}1", Vba.formatCurrency(1.0, 0)
    assert_equal "#{cs}.10", Vba.formatCurrency(0.10, -1, 0)
    assert_equal "#{cs}0.10", Vba.formatCurrency(0.10, -1, -1)
    # useParensForNegativeNumbers is not implemented (see Vba.java todo comment),
    # so the output depends on the locale's default negative currency format.
    expected_neg = fmt.format(-0.10)
    assert_equal expected_neg, Vba.formatCurrency(-0.10, -1, -1, 0)

    assert_equal "#{cs}1,000.00", Vba.formatCurrency(1000.0, -1, -1, 0, 0)
    assert_equal "#{cs}1000.00", Vba.formatCurrency(1000.0, -1, -1, 0, -1)
  end

  # Java: VbaTest#testTypeName
  it "typeName" do
    assert_equal "Double", Vba.typeName(1.0)
    assert_equal "Integer", Vba.typeName(java.lang.Integer.new(1))
    assert_equal "Float", Vba.typeName(java.lang.Float.new(1.0))
    assert_equal "Byte", Vba.typeName(java.lang.Byte.new(1))
    assert_equal "NULL", Vba.typeName(nil)
    assert_equal "String", Vba.typeName("")
    assert_equal "Date", Vba.typeName(java.util.Date.new)
  end

  # Financial

  # Java: VbaTest#testFv
  it "fV" do
    # r=0, n=3, y=2, p=7, t=true
    f = Vba.fV(0, 3, 2, 7, true)
    assert_equal(-13.0, f)

    # r=1, n=10, y=100, p=10000, t=false
    f = Vba.fV(1, 10, 100, 10000, false)
    assert_equal(-10342300.0, f)

    # r=1, n=10, y=100, p=10000, t=true
    f = Vba.fV(1, 10, 100, 10000, true)
    assert_equal(-10444600.0, f)

    # r=2, n=12, y=120, p=12000, t=false
    f = Vba.fV(2, 12, 120, 12000, false)
    assert_equal(-6409178400.0, f)

    # r=2, n=12, y=120, p=12000, t=true
    f = Vba.fV(2, 12, 120, 12000, true)
    assert_equal(-6472951200.0, f)

    # cross tests with pv
    f = Vba.fV(2.95, 13, 13000, -4406.78544294496, false)
    assert_in_delta 333891.230010986, f, 1e-2

    f = Vba.fV(2.95, 13, 13000, -17406.7852148156, true)
    assert_in_delta 333891.230102539, f, 1e-2
  end

  # Java: VbaTest#testNpv
  it "nPV" do
    v = [100, 200, 300, 400].to_java(:double)
    assert_equal 162.5, Vba.nPV(1, v)

    v = [1000, 666.66666, 333.33, 12.2768416].to_java(:double)
    assert_in_delta 347.99232604144827, Vba.nPV(2.5, v), SMALL

    v = [1000, 0, -900, -7777.5765].to_java(:double)
    assert_in_delta 74.3742433377061, Vba.nPV(12.33333, v), 1e-12

    v = [200000, 300000.55, 400000, 1000000, 6000000, 7000000, -300000].to_java(:double)
    assert_in_delta 11342283.4233124, Vba.nPV(0.05, v), 1e-8
  end

  # Java: VbaTest#testPmt
  it "pmt" do
    # r=0, n=3, p=2, f=7, t=true
    y = Vba.pmt(0, 3, 2, 7, true)
    assert_equal(-3.0, y)

    # cross check with pv
    y = Vba.pmt(1, 10, -109.66796875, 10000, false)
    assert_equal 100.0, y

    y = Vba.pmt(1, 10, -209.5703125, 10000, true)
    assert_equal 100.0, y

    # cross check with fv
    y = Vba.pmt(2, 12, 12000, -6409178400.0, false)
    assert_equal 120.0, y

    y = Vba.pmt(2, 12, 12000, -6472951200.0, true)
    assert_equal 120.0, y
  end

  # Java: VbaTest#testPv
  it "pV" do
    # r=0, n=3, y=2, f=7, t=true
    f = Vba.pV(0, 3, 2, 7, true)
    assert_equal(-13.0, f)

    # r=1, n=10, y=100, f=10000, t=false
    p = Vba.pV(1, 10, 100, 10000, false)
    assert_equal(-109.66796875, p)

    # r=1, n=10, y=100, f=10000, t=true
    p = Vba.pV(1, 10, 100, 10000, true)
    assert_equal(-209.5703125, p)

    p = Vba.pV(2.95, 13, 13000, 333891.23, false)
    assert_in_delta(-4406.78544294496, p, 1e-10)

    p = Vba.pV(2.95, 13, 13000, 333891.23, true)
    assert_in_delta(-17406.7852148156, p, 1e-10)

    # cross tests with fv
    p = Vba.pV(2, 12, 120, -6409178400.0, false)
    assert_equal 12000.0, p

    p = Vba.pV(2, 12, 120, -6472951200.0, true)
    assert_equal 12000.0, p
  end

  # Java: VbaTest#testDdb
  it "dDB" do
    result = Vba.dDB(100, 0, 10, 1, 2)
    assert_equal 20.0, result
    result = Vba.dDB(100, 0, 10, 2, 2)
    assert_equal 40.0, result
    result = Vba.dDB(100, 0, 10, 3, 2)
    assert_equal 60.0, result
    result = Vba.dDB(100, 0, 10, 4, 2)
    assert_equal 80.0, result
  end

  # Java: VbaTest#testRate
  it "rate" do
    # compare rate to pV calculation
    exp_rate = 0.0083333
    exp_pv = Vba.pV(exp_rate, 12 * 30, -877.57, 0, false)
    result = Vba.rate(12 * 30, -877.57, exp_pv, 0, false, 0.10 / 12)
    assert (exp_rate - result).abs < 0.0000001

    # compare rate to fV calculation
    exp_fv = Vba.fV(exp_rate, 12, -100, 0, false)
    result = Vba.rate(12, -100, 0, exp_fv, false, 0.10 / 12)
    assert (exp_rate - result).abs < 0.0000001
  end

  # Java: VbaTest#testIRR
  it "IRR" do
    vals = [-1000, 50, 50, 50, 50, 50, 1050].to_java(:double)
    assert (0.05 - Vba.IRR(vals, 0.1)).abs < 0.0000001

    vals = [-1000, 200, 200, 200, 200, 200, 200].to_java(:double)
    assert (0.05471796 - Vba.IRR(vals, 0.1)).abs < 0.0000001

    # what happens if the numbers are inversed?
    vals = [1000, -200, -200, -200, -200, -200, -200].to_java(:double)
    assert (0.05471796 - Vba.IRR(vals, 0.1)).abs < 0.0000001
  end

  # Java: VbaTest#testMIRR
  it "MIRR" do
    vals = [-1000, 50, 50, 50, 50, 50, 1050].to_java(:double)
    assert (0.05 - Vba.MIRR(vals, 0.05, 0.05)).abs < 0.0000001

    vals = [-1000, 200, 200, 200, 200, 200, 200].to_java(:double)
    assert (0.05263266 - Vba.MIRR(vals, 0.05, 0.05)).abs < 0.0000001

    vals = [-1000, 200, 200, 200, 200, 200, 200].to_java(:double)
    assert (0.04490701 - Vba.MIRR(vals, 0.06, 0.04)).abs < 0.0000001
  end

  # Java: VbaTest#testIPmt
  it "iPmt" do
    assert_equal(-10000.0, Vba.iPmt(0.10, 1, 30, 100000, 0, false))
    assert_equal(-2185.473324557822, Vba.iPmt(0.10, 15, 30, 100000, 0, false))
    assert_equal(-60.79248252633988, Vba.iPmt(0.10, 30, 30, 100000, 0, false))
  end

  # Java: VbaTest#testPPmt
  it "pPmt" do
    assert_equal(-607.9248252633897, Vba.pPmt(0.10, 1, 30, 100000, 0, false))
    assert_equal(-8422.451500705567, Vba.pPmt(0.10, 15, 30, 100000, 0, false))
    assert_equal(-10547.13234273705, Vba.pPmt(0.10, 30, 30, 100000, 0, false))

    # verify that pmt, ipmt, and ppmt add up
    pmt = Vba.pmt(0.10, 30, 100000, 0, false)
    ipmt = Vba.iPmt(0.10, 15, 30, 100000, 0, false)
    ppmt = Vba.pPmt(0.10, 15, 30, 100000, 0, false)
    assert (pmt - (ipmt + ppmt)).abs < 0.0000001
  end

  # Java: VbaTest#testSLN
  it "sLN" do
    assert_equal 18.0, Vba.sLN(100, 10, 5)
    assert_equal java.lang.Double::POSITIVE_INFINITY, Vba.sLN(100, 10, 0)
  end

  # Java: VbaTest#testSYD
  it "sYD" do
    assert_equal 300.0, Vba.sYD(1000, 100, 5, 5)
    assert_equal 240.0, Vba.sYD(1000, 100, 4, 5)
    assert_equal 180.0, Vba.sYD(1000, 100, 3, 5)
    assert_equal 120.0, Vba.sYD(1000, 100, 2, 5)
    assert_equal 60.0, Vba.sYD(1000, 100, 1, 5)
  end

  # Java: VbaTest#testInStr
  it "inStr" do
    assert_equal 1, Vba.inStr("the quick brown fox jumps over the lazy dog", "the")
    assert_equal 32, Vba.inStr(16, "the quick brown fox jumps over the lazy dog", "the")
    assert_equal 0, Vba.inStr(16, "the quick brown fox jumps over the lazy dog", "cat")
    assert_equal 0, Vba.inStr(1, "the quick brown fox jumps over the lazy dog", "cat")
    assert_equal 0, Vba.inStr(1, "", "cat")
    assert_equal 0, Vba.inStr(100, "short string", "str")
    error = assert_raises(InvalidArgumentException) do
      Vba.inStr(0, "the quick brown fox jumps over the lazy dog", "the")
    end
    assert_includes error.message, "-1 or a location"
  end

  # Java: VbaTest#testInStrRev
  it "inStrRev" do
    assert_equal 32, Vba.inStrRev("the quick brown fox jumps over the lazy dog", "the")
    assert_equal 1, Vba.inStrRev("the quick brown fox jumps over the lazy dog", "the", 16)
    error = assert_raises(InvalidArgumentException) do
      Vba.inStrRev("the quick brown fox jumps over the lazy dog", "the", 0)
    end
    assert_includes error.message, "-1 or a location"
  end

  # Java: VbaTest#testStrComp
  it "strComp" do
    assert_equal(-1, Vba.strComp("a", "b", 0))
    assert_equal 0, Vba.strComp("a", "a", 0)
    assert_equal 1, Vba.strComp("b", "a", 0)
  end

  # Java: VbaTest#testNper
  it "nPer" do
    # r=0, y=7, p=2, f=3, t=false
    n = Vba.nPer(0, 7, 2, 3, false)
    assert_in_delta(-0.71428571429, n, 1e-10)

    # cross check with pv
    n = Vba.nPer(1, 100, -109.66796875, 10000, false)
    assert_in_delta 10.0, n, 1e-12

    n = Vba.nPer(1, 100, -209.5703125, 10000, true)
    assert_in_delta 10.0, n, 1e-14

    # cross check with fv
    n = Vba.nPer(2, 120, 12000, -6409178400.0, false)
    assert_in_delta 12.0, n, SMALL

    n = Vba.nPer(2, 120, 12000, -6472951200.0, true)
    assert_in_delta 12.0, n, SMALL
  end

  # String functions

  # Java: VbaTest#testAsc
  it "asc" do
    assert_equal 0x61, Vba.asc("abc")
    assert_equal 0x1234, Vba.asc("\u1234abc")
    error = assert_raises(java.lang.RuntimeException) { Vba.asc("") }
    assert_message error, "StringIndexOutOfBoundsException"
  end

  # Java: VbaTest#testAscB
  it "ascB" do
    assert_equal 0x61, Vba.ascB("abc")
    assert_equal 0x34, Vba.ascB("\u1234abc") # not sure about this
    error = assert_raises(java.lang.RuntimeException) { Vba.ascB("") }
    assert_message error, "StringIndexOutOfBoundsException"
  end

  # Java: VbaTest#testAscW
  it "ascW" do
    # ascW behaves identically to asc
    assert_equal 0x61, Vba.ascW("abc")
    assert_equal 0x1234, Vba.ascW("\u1234abc")
    error = assert_raises(java.lang.RuntimeException) { Vba.ascW("") }
    assert_message error, "StringIndexOutOfBoundsException"
  end

  # Java: VbaTest#testChr
  it "chr" do
    assert_equal "a", Vba.chr(0x61)
    assert_equal "\u1234", Vba.chr(0x1234)
  end

  # Java: VbaTest#testChrB
  it "chrB" do
    assert_equal "a", Vba.chrB(0x61)
    assert_equal "\u0034", Vba.chrB(0x1234)
  end

  # Java: VbaTest#testChrW
  it "chrW" do
    assert_equal "a", Vba.chrW(0x61)
    assert_equal "\u1234", Vba.chrW(0x1234)
  end

  # Java: VbaTest#testLCase
  it "lCase" do
    assert_equal "", Vba.lCase("")
    assert_equal "abc", Vba.lCase("AbC")
  end

  # Java: VbaTest#testLeft
  it "left" do
    assert_equal "abc", Vba.left("abcxyz", 3)
    # length=0 is OK
    assert_equal "", Vba.left("abcxyz", 0)
    # Spec says: "If greater than or equal to the number of characters in
    # string, the entire string is returned."
    assert_equal "abcxyz", Vba.left("abcxyz", 8)
    assert_equal "", Vba.left("", 3)

    # Length<0 is illegal (Bug.Ssas2005Compatible is false)
    error = assert_raises(java.lang.RuntimeException) { Vba.left("xyz", -2) }
    assert_message error, "StringIndexOutOfBoundsException"

    assert_equal "Hello", Vba.left("Hello World!", 5)
  end

  # Java: VbaTest#testLTrim
  it "lTrim" do
    assert_equal "", Vba.lTrim("")
    assert_equal "", Vba.lTrim("  ")
    assert_equal "abc  \r", Vba.lTrim(" \n\tabc  \r")
  end

  # Java: VbaTest#testMid
  it "mid" do
    test_string = "Mid Function Demo"
    assert_equal "Mid", Vba.mid(test_string, 1, 3)
    assert_equal "Demo", Vba.mid(test_string, 14, 4)
    # It's OK if start+length = string.length
    assert_equal "Demo", Vba.mid(test_string, 14, 5)
    # It's OK if start+length > string.length
    assert_equal "Demo", Vba.mid(test_string, 14, 500)
    assert_equal "Function Demo", Vba.mid(test_string, 5)
    assert_equal "o", Vba.mid("yahoo", 5, 1)

    # Start=0 illegal (Bug.Ssas2005Compatible is false)
    error = assert_raises(java.lang.RuntimeException) { Vba.mid(test_string, 0) }
    assert_message error, "Invalid parameter. Start parameter of Mid function must be positive"

    # Start<0 illegal
    error = assert_raises(java.lang.RuntimeException) { Vba.mid(test_string, -2) }
    assert_message error, "Invalid parameter. Start parameter of Mid function must be positive"

    # Start<0 illegal to 3 args version
    error = assert_raises(java.lang.RuntimeException) { Vba.mid(test_string, -2, 5) }
    assert_message error, "Invalid parameter. Start parameter of Mid function must be positive"

    # Length=0 OK
    assert_equal "", Vba.mid(test_string, 14, 0)

    # Length<0 illegal (Bug.Ssas2005Compatible is false)
    error = assert_raises(java.lang.RuntimeException) { Vba.mid(test_string, 14, -1) }
    assert_message error, "Invalid parameter. Length parameter of Mid function must be non-negative"
  end

  # Java: VbaTest#testMonthName
  it "monthName" do
    assert_equal "January", Vba.monthName(1, false)
    assert_equal "Jan", Vba.monthName(1, true)
    assert_equal "Dec", Vba.monthName(12, true)
    error = assert_raises(java.lang.RuntimeException) { Vba.monthName(0, true) }
    assert_message error, "ArrayIndexOutOfBoundsException"
  end

  # Java: VbaTest#testReplace3
  it "replace with 3 args" do
    # replace with longer string
    assert_equal "abczabcz", Vba.replace("xyzxyz", "xy", "abc")
    # replace with shorter string
    assert_equal "wazwaz", Vba.replace("wxyzwxyz", "xy", "a")
    # replace with string which contains seek
    assert_equal "wxyz", Vba.replace("xyz", "xy", "wxy")
    # replace with string which combines with following char to make seek
    assert_equal "wxyzwx", Vba.replace("xyyzxy", "xy", "wx")
    # replace with empty string
    assert_equal "wxyza", Vba.replace("wxxyyzxya", "xy", "")
  end

  # Java: VbaTest#testReplace4
  it "replace with 4 args" do
    assert_equal "azaz", Vba.replace("xyzxyz", "xy", "a", 1)
    assert_equal "xyzaz", Vba.replace("xyzxyz", "xy", "a", 2)
    assert_equal "xyzxyz", Vba.replace("xyzxyz", "xy", "a", 30)
    # spec doesn't say, but assume starting before start of string is ok
    assert_equal "azaz", Vba.replace("xyzxyz", "xy", "a", 0)
    assert_equal "azaz", Vba.replace("xyzxyz", "xy", "a", -5)
  end

  # Java: VbaTest#testReplace5
  it "replace with 5 args" do
    assert_equal "azaz", Vba.replace("xyzxyz", "xy", "a", 1, -1)
    assert_equal "azxyz", Vba.replace("xyzxyz", "xy", "a", 1, 1)
    assert_equal "azaz", Vba.replace("xyzxyz", "xy", "a", 1, 2)
    assert_equal "xyzazxyz", Vba.replace("xyzxyzxyz", "xy", "a", 2, 1)
  end

  # Java: VbaTest#testReplace6
  it "replace with 6 args" do
    # compare is currently ignored
    assert_equal "azaz", Vba.replace("xyzxyz", "xy", "a", 1, -1, 1000)
    assert_equal "azxyz", Vba.replace("xyzxyz", "xy", "a", 1, 1, 0)
    assert_equal "azaz", Vba.replace("xyzxyz", "xy", "a", 1, 2, -6)
    assert_equal "xyzazxyz", Vba.replace("xyzxyzxyz", "xy", "a", 2, 1, 11)
  end

  # Java: VbaTest#testRight
  it "right" do
    assert_equal "xyz", Vba.right("abcxyz", 3)
    # length=0 is OK
    assert_equal "", Vba.right("abcxyz", 0)
    # Spec says: "If greater than or equal to the number of characters in
    # string, the entire string is returned."
    assert_equal "abcxyz", Vba.right("abcxyz", 8)
    assert_equal "", Vba.right("", 3)

    # The VBA spec says that length<0 is error (Bug.Ssas2005Compatible is false)
    error = assert_raises(java.lang.RuntimeException) { Vba.right("xyz", -2) }
    assert_message error, "StringIndexOutOfBoundsException"

    assert_equal "World!", Vba.right("Hello World!", 6)
  end

  # Java: VbaTest#testRTrim
  it "rTrim" do
    assert_equal "", Vba.rTrim("")
    assert_equal "", Vba.rTrim("  ")
    assert_equal " \n\tabc", Vba.rTrim(" \n\tabc")
    assert_equal " \n\tabc", Vba.rTrim(" \n\tabc  \r")
  end

  # Java: VbaTest#testSpace
  it "space" do
    assert_equal "   ", Vba.space(3)
    assert_equal "", Vba.space(0)
    error = assert_raises(java.lang.RuntimeException) { Vba.space(-2) }
    assert_message error, "NegativeArraySizeException"
  end

  # Java: VbaTest#testString
  it "string" do
    assert_equal "xxx", Vba.string(3, 'x'.ord)
    assert_equal "", Vba.string(0, 'y'.ord)
    error = assert_raises(java.lang.RuntimeException) { Vba.string(-2, 'z'.ord) }
    assert_message error, "NegativeArraySizeException"
    assert_equal "", Vba.string(100, 0)
  end

  # Java: VbaTest#testStrReverse
  it "strReverse" do
    # odd length
    assert_equal "cba", Vba.strReverse("abc")
    # even length
    assert_equal "wxyz", Vba.strReverse("zyxw")
    # zero length
    assert_equal "", Vba.strReverse("")
  end

  # Java: VbaTest#testTrim
  it "trim" do
    assert_equal "", Vba.trim("")
    assert_equal "", Vba.trim("  ")
    assert_equal "abc", Vba.trim("abc")
    assert_equal "abc", Vba.trim(" \n\tabc  \r")
  end

  # Java: VbaTest#testWeekdayName
  it "weekdayName" do
    # If Sunday (1) is the first day of the week
    # then day 1 is Sunday,
    # then day 2 is Monday,
    # and day 7 is Saturday
    assert_equal "Sunday", Vba.weekdayName(1, false, 1)
    assert_equal "Monday", Vba.weekdayName(2, false, 1)
    assert_equal "Saturday", Vba.weekdayName(7, false, 1)
    assert_equal "Sat", Vba.weekdayName(7, true, 1)

    # If Monday (2) is the first day of the week
    # then day 1 is Monday,
    # and day 7 is Sunday
    assert_equal "Monday", Vba.weekdayName(1, false, 2)
    assert_equal "Sunday", Vba.weekdayName(7, false, 2)

    # Use weekday start from locale. Test for the 2 most common.
    case Calendar.getInstance.getFirstDayOfWeek
    when Calendar::SUNDAY
      assert_equal "Sunday", Vba.weekdayName(1, false, 0)
      assert_equal "Monday", Vba.weekdayName(2, false, 0)
      assert_equal "Saturday", Vba.weekdayName(7, false, 0)
      assert_equal "Sat", Vba.weekdayName(7, true, 0)
    when Calendar::MONDAY
      assert_equal "Monday", Vba.weekdayName(1, false, 0)
      assert_equal "Tuesday", Vba.weekdayName(2, false, 0)
      assert_equal "Sunday", Vba.weekdayName(7, false, 0)
      assert_equal "Sun", Vba.weekdayName(7, true, 0)
    end
  end

  # Mathematical

  # Java: VbaTest#testAbs
  it "abs" do
    assert_equal 1.7, Vba.abs(-1.7)
  end

  # Java: VbaTest#testAtn
  it "atn" do
    assert_in_delta 0.0, Vba.atn(0), SMALL
    assert_in_delta Math::PI / 4.0, Vba.atn(1), SMALL
  end

  # Java: VbaTest#testCos
  it "cos" do
    assert_in_delta 1.0, Vba.cos(0), 0.0
    assert_in_delta Vba.sqr(0.5), Vba.cos(Math::PI / 4.0), 0.0
    assert_in_delta 0.0, Vba.cos(Math::PI / 2.0), SMALL
    assert_in_delta(-1.0, Vba.cos(Math::PI), 0.0)
  end

  # Java: VbaTest#testExp
  it "exp" do
    assert_equal 1.0, Vba.exp(0)
    assert_in_delta Math::E, Vba.exp(1), 1e-10
  end

  # Java: VbaTest#testRound
  it "round" do
    assert_in_delta 123.0, Vba.round(123.4567), SMALL
  end

  # Java: VbaTest#testRound2
  it "round with 2 args" do
    assert_in_delta 123.0, Vba.round(123.4567, 0), SMALL
    assert_in_delta 123.46, Vba.round(123.4567, 2), SMALL
    assert_in_delta 120.0, Vba.round(123.45, -1), SMALL
    assert_in_delta(-123.46, Vba.round(-123.4567, 2), SMALL)
  end

  # Java: VbaTest#testSgn
  it "sgn" do
    assert_in_delta 1, Vba.sgn(3.11111), 0.0
    assert_in_delta(-1, Vba.sgn(-Math::PI), 0.0)
    assert_equal true, 0 == Vba.sgn(-0.0)
    assert_equal true, 0 == Vba.sgn(0.0)
  end

  # Java: VbaTest#testSin
  it "sin" do
    assert_in_delta Vba.sqr(0.5), Vba.sin(Math::PI / 4.0), SMALL
  end

  # Java: VbaTest#testSqr
  it "sqr" do
    assert_in_delta 2.0, Vba.sqr(4.0), 0.0
    assert_in_delta 0.0, Vba.sqr(0.0), 0.0
    assert_equal true, java.lang.Double.isNaN(Vba.sqr(-4))
  end

  # Java: VbaTest#testTan
  it "tan" do
    assert_in_delta 1.0, Vba.tan(Math::PI / 4.0), SMALL
  end
end
