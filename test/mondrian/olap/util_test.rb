# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2004-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# ArrayList subclass that throws on get/iterator for testNullValuesMap
class ThrowingArrayList < java.util.ArrayList
  def get(index)
    raise java.lang.RuntimeException.new("BaconationException")
  end

  def iterator
    raise java.lang.RuntimeException.new("BaconationException")
  end
end

# Java: mondrian/olap/UtilTestCase.java
describe "Util" do
  Util = Java::MondrianOlap::Util
  Id = Java::MondrianOlap::Id

  def assert_connect_string_property(connect_string, name, expected_value)
    list = Util.parseConnectString(connect_string)
    assert_equal expected_value, list.get(name)
  end

  def segment_name(segments, index)
    segments.get(index).name
  end

  def check_replace(original, seek, replace_str, expected)
    # Check the StringBuilder version of replace
    buf = java.lang.StringBuilder.new(original)
    buf2 = Util.replace(buf, 0, seek, replace_str)
    assert_equal expected, buf.toString
    assert_equal expected, buf2.toString
    assert_same buf, buf2

    # Check the String version of replace
    assert_equal expected, Util.replace(original, seek, replace_str)
  end

  def check_moniker_valid(moniker)
    valid_chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz$_"
    digits = "0123456789"
    assert moniker.length > 0
    moniker.length.times do |i|
      assert valid_chars.include?(moniker[i]), "Invalid char in moniker: #{moniker}"
    end
    refute digits.include?(moniker[0]), "Moniker starts with digit: #{moniker}"
  end

  def check_cartesian_list_contents(list)
    array_list = java.util.ArrayList.new
    list.each { |element| array_list.add(element) }
    assert_equal array_list, list
  end

  def check_to_string(expected, set)
    assert_equal expected, set.toString

    list = java.util.ArrayList.new
    list.addAll(set)
    assert_equal expected, list.toString

    list.clear
    set.each { |s| list.add(s) }
    assert_equal expected, list.toString
  end

  describe "connect string parsing" do
    # Java: UtilTestCase#testParseConnectStringSimple
    it "parses simple connect string" do
      properties = Util.parseConnectString("foo=x;bar=y;foo=z")
      assert_equal "y", properties.get("bar")
      assert_equal "y", properties.get("BAR")
      assert_nil properties.get(" bar")
      assert_equal "z", properties.get("foo")
      assert_nil properties.get("kipper")
      assert_equal 2, properties.count
      assert_equal "foo=z; bar=y", properties.toString
    end

    # Java: UtilTestCase#testParseConnectStringComplex
    it "parses complex connect string" do
      properties = Util.parseConnectString(
        "normalProp=value;" \
        "emptyValue=;" \
        " spaceBeforeProp=abc;" \
        " spaceBeforeAndAfterProp =def;" \
        " space in prop = foo bar ;" \
        "equalsInValue=foo=bar;" \
        "semiInProp;Name=value;" \
        " singleQuotedValue = 'single quoted value ending in space ' ;" \
        ' doubleQuotedValue = "=double quoted value preceded by equals" ;' \
        " singleQuotedValueWithSemi = 'one; two';" \
        " singleQuotedValueWithSpecials = 'one; two \"three''four=five'"
      )
      assert_equal 11, properties.count
      assert_equal "value", properties.get("normalProp")
      assert_equal "", properties.get("emptyValue")
      assert_equal "abc", properties.get("spaceBeforeProp")
      assert_equal "def", properties.get("spaceBeforeAndAfterProp")
      assert_equal "foo bar", properties.get("space in prop")
      assert_equal "foo=bar", properties.get("equalsInValue")
      assert_equal "value", properties.get("semiInProp;Name")
      assert_equal "single quoted value ending in space ", properties.get("singleQuotedValue")
      assert_equal "=double quoted value preceded by equals", properties.get("doubleQuotedValue")
      assert_equal "one; two", properties.get("singleQuotedValueWithSemi")
      assert_equal "one; two \"three'four=five", properties.get("singleQuotedValueWithSpecials")

      assert_equal(
        "normalProp=value;" \
        " emptyValue=;" \
        " spaceBeforeProp=abc;" \
        " spaceBeforeAndAfterProp=def;" \
        " space in prop=foo bar;" \
        " equalsInValue=foo=bar;" \
        " semiInProp;Name=value;" \
        " singleQuotedValue=single quoted value ending in space ;" \
        " doubleQuotedValue==double quoted value preceded by equals;" \
        " singleQuotedValueWithSemi='one; two';" \
        " singleQuotedValueWithSpecials='one; two \"three''four=five'",
        properties.toString
      )
    end

    # Java: UtilTestCase#testConnectStringMore
    it "handles single and double quote escaping" do
      assert_connect_string_property("singleQuote=''''", "singleQuote", "'")
      assert_connect_string_property('doubleQuote=""""', "doubleQuote", '"')
      assert_connect_string_property("empty= ;foo=bar", "empty", "")
    end

    # Java: UtilTestCase#testBugMondrian397
    it "handles MONDRIAN-397 edge cases" do
      properties = Util.parseConnectString("foo=true; bar=xxx;")
      assert_equal 2, properties.count

      properties = Util.parseConnectString("foo=true; bar=xxx; ")
      assert_equal 2, properties.count

      properties = Util.parseConnectString("   ")
      assert_equal 0, properties.count

      properties = Util.parseConnectString(
        "provider=mondrian; JdbcDrivers=org.hsqldb.jdbcDriver;" \
        "Jdbc=jdbc:hsqldb:./sql/sampledata;" \
        "Catalog=C:\\cygwin\\home\\src\\jfreereport\\engines\\classic" \
        "\\extensions-mondrian\\demo\\steelwheels.mondrian.xml;" \
        "JdbcUser=sa; JdbcPassword=; "
      )
      assert_equal 6, properties.count
      assert_equal "", properties.get("JdbcPassword")
    end

    # Java: UtilTestCase#testOleDbSpec
    it "follows OLE DB spec for connect strings" do
      assert_connect_string_property("Provider='MSDASQL'", "Provider", "MSDASQL")
      assert_connect_string_property("Provider='MSDASQL.1'", "Provider", "MSDASQL.1")

      assert_connect_string_property(
        "Provider='MSDASQL';Location='3Northwind'", "Location", "3Northwind"
      )
      assert_connect_string_property(
        "Jet OLE DB:System Database=c:\\system.mda",
        "Jet OLE DB:System Database", "c:\\system.mda"
      )
      assert_connect_string_property(
        "Authentication;Info=Column 5", "Authentication;Info", "Column 5"
      )
      # Equal sign in keyword must be preceded by additional equal sign
      assert_connect_string_property("Verification==Security=True", "Verification=Security", "True")
      assert_connect_string_property("Many====One=Valid", "Many==One", "Valid")
      assert_connect_string_property("TooMany===False", "TooMany=", "False")

      # Setting values that use reserved characters
      assert_connect_string_property(
        "ExtendedProperties=\"Integrated Security='SSPI';Initial Catalog='Northwind'\"",
        "ExtendedProperties",
        "Integrated Security='SSPI';Initial Catalog='Northwind'"
      )
      assert_connect_string_property(
        "ExtendedProperties='Integrated Security=\"SSPI\";Databse=\"My Northwind DB\"'",
        "ExtendedProperties",
        'Integrated Security="SSPI";Databse="My Northwind DB"'
      )
      assert_connect_string_property("DataSchema='\"MyCustTable\"'", "DataSchema", '"MyCustTable"')
      assert_connect_string_property(
        "DataSchema=\"'MyOtherCustTable'\"", "DataSchema", "'MyOtherCustTable'"
      )
      # Both single and double quotes in value
      assert_connect_string_property(
        "NewRecordsCaption='\"Company''s \"new\" customer\"'",
        "NewRecordsCaption", "\"Company's \"new\" customer\""
      )
      assert_connect_string_property(
        'NewRecordsCaption="""Company' + "'" + 's ""new"" customer"""',
        "NewRecordsCaption", "\"Company's \"new\" customer\""
      )

      # Spaces
      assert_connect_string_property("MyKeyword=My Value", "MyKeyword", "My Value")
      assert_connect_string_property("MyKeyword= My Value ;MyNextValue=Value", "MyKeyword", "My Value")
      assert_connect_string_property("MyKeyword=' My Value  '", "MyKeyword", " My Value  ")
      assert_connect_string_property('MyKeyword="  My Value "', "MyKeyword", "  My Value ")

      # Listing keywords multiple times — last occurrence wins
      assert_connect_string_property(
        "Provider='MSDASQL';Location='Northwind';" \
        "Cache Authentication='True';Prompt='Complete';" \
        "Location='Customers'",
        "Location", "Customers"
      )
      # Exception: Provider keyword uses first occurrence
      assert_connect_string_property(
        "Provider='MSDASQL';Location='Northwind'; Provider='SQLOLEDB'",
        "Provider", "MSDASQL"
      )
    end

    # Java: UtilTestCase#testConvertConnectString
    it "converts olap4j connect string to native Mondrian" do
      assert_equal(
        "Provider=Mondrian; Datasource=jdbc/SampleData;Catalog=foodmart/FoodMart.xml;",
        Util.convertOlap4jConnectStringToNativeMondrian(
          "jdbc:mondrian:Datasource=jdbc/SampleData;Catalog=foodmart/FoodMart.xml;"
        )
      )
    end
  end

  describe "string utilities" do
    # Java: UtilTestCase#testQuoteMdxIdentifier
    it "quotes MDX identifiers" do
      assert_equal "[San Francisco]", Util.quoteMdxIdentifier("San Francisco")
      assert_equal "[a [bracketed]] string]", Util.quoteMdxIdentifier("a [bracketed] string")
      assert_equal(
        "[Store].[USA].[California]",
        Util.quoteMdxIdentifier(
          java.util.Arrays.asList(
            Id::NameSegment.new("Store"),
            Id::NameSegment.new("USA"),
            Id::NameSegment.new("California")
          )
        )
      )
    end

    # Java: UtilTestCase#testQuoteJava
    it "quotes Java strings" do
      assert_equal '"San Francisco"', Util.quoteJavaString("San Francisco")
      assert_equal '"null"', Util.quoteJavaString("null")
      assert_equal "null", Util.quoteJavaString(nil)
      assert_equal '"a\\\\b\\"c"', Util.quoteJavaString('a\\b"c')
    end

    # Java: UtilTestCase#testBufReplace
    it "replaces substrings in buffers and strings" do
      check_replace("xoxox", "x", "yy", "yyoyyoyy")
      check_replace("xxoxxoxx", "xx", "z", "zozoz")
      check_replace("xxoxxoxx", "xx", "", "oo")
      check_replace("xox", "x", "xx", "xxoxx")
      check_replace("cacab", "cab", "bb", "cabb")
      check_replace("the quick brown fox", "coyote", "wolf", "the quick brown fox")
      check_replace("", "coyote", "wolf", "")
      check_replace("fox", "", "dog", "dogfdogodogxdog")
    end
  end

  describe "identifier utilities" do
    # Java: UtilTestCase#testImplode
    it "implodes identifier segments" do
      foo_bar = java.util.Arrays.asList(
        Id::NameSegment.new("foo", Id::Quoting::UNQUOTED),
        Id::NameSegment.new("bar", Id::Quoting::UNQUOTED)
      )
      assert_equal "[foo].[bar]", Util.implode(foo_bar)

      empty = java.util.Collections.emptyList
      assert_equal "", Util.implode(empty)

      nasty = java.util.Arrays.asList(
        Id::NameSegment.new("string", Id::Quoting::UNQUOTED),
        Id::NameSegment.new("with", Id::Quoting::UNQUOTED),
        Id::NameSegment.new("a [bracket] in it", Id::Quoting::UNQUOTED)
      )
      assert_equal "[string].[with].[a [bracket]] in it]", Util.implode(nasty)
    end

    # Java: UtilTestCase#testParseIdentifier
    it "parses identifiers" do
      segments = Util.parseIdentifier("[string].[with].[a [bracket]] in it]")
      assert_equal 3, segments.size
      assert_equal "a [bracket] in it", segment_name(segments, 2)

      segments = Util.parseIdentifier("[Worklog].[All].[calendar-[LANGUAGE]].js]")
      assert_equal 3, segments.size
      assert_equal "calendar-[LANGUAGE].js", segment_name(segments, 2)

      # allow spaces before, after and between
      segments = Util.parseIdentifier("  [foo] . [bar].[baz]  ")
      assert_equal 3, segments.size
      assert_equal "foo", segment_name(segments, 0)

      # first segment not quoted
      segments = Util.parseIdentifier("Time.1997.[Q3]")
      assert_equal 3, segments.size
      assert_equal "Time", segment_name(segments, 0)
      assert_equal "1997", segment_name(segments, 1)
      assert_equal "Q3", segment_name(segments, 2)

      # spaces ignored after unquoted segment
      segments = Util.parseIdentifier("[Time . Weekly ] . 1997 . [Q3]")
      assert_equal 3, segments.size
      assert_equal "Time . Weekly ", segment_name(segments, 0)
      assert_equal "1997", segment_name(segments, 1)
      assert_equal "Q3", segment_name(segments, 2)

      # identifier ending in '.' is invalid
      error = assert_raises(java.lang.IllegalArgumentException) do
        Util.parseIdentifier("[foo].[bar].")
      end
      assert_equal(
        "Expected identifier after '.', in member identifier '[foo].[bar].'",
        error.message
      )

      error = assert_raises(java.lang.IllegalArgumentException) do
        Util.parseIdentifier("[foo].[bar")
      end
      assert_equal "Expected ']', in member identifier '[foo].[bar'", error.message

      error = assert_raises(java.lang.IllegalArgumentException) do
        Util.parseIdentifier("[Foo].[Bar], [Baz]")
      end
      assert_equal "Invalid member identifier '[Foo].[Bar], [Baz]'", error.message
    end
  end

  describe "property replacement" do
    # Java: UtilTestCase#testReplaceProperties
    it "replaces properties in strings" do
      map = java.util.HashMap.new
      map.put("foo", "bar")
      map.put("empty", "")
      map.put("null", nil)
      map.put("foobarbaz", "bang!")
      map.put("malformed${foo", "groovy")

      assert_equal "abarb", Util.replaceProperties("a${foo}b", map)
      assert_equal "twicebarbar", Util.replaceProperties("twice${foo}${foo}", map)
      assert_equal "bar at start", Util.replaceProperties("${foo} at start", map)
      assert_equal "xyz", Util.replaceProperties("x${empty}y${empty}${empty}z", map)
      assert_equal "x${nonexistent}bar", Util.replaceProperties("x${nonexistent}${foo}", map)

      # malformed tokens are left as is
      assert_equal "${malformedbarbar", Util.replaceProperties("${malformed${foo}${foo}", map)

      # string can contain '$'
      assert_equal "x$foo", Util.replaceProperties("x$foo", map)

      # property with empty name is always ignored
      assert_equal "${}", Util.replaceProperties("${}", map)
      map.put("", "v")
      assert_equal "${}", Util.replaceProperties("${}", map)

      # if a property's value is null, it's as if it doesn't exist
      assert_equal "${null}", Util.replaceProperties("${null}", map)

      # nested properties are expanded, but not recursively
      assert_equal "${foobarbaz}", Util.replaceProperties("${foo${foo}baz}", map)
    end
  end

  describe "wildcard and camel" do
    # Java: UtilTestCase#testWildcard
    it "converts wildcards to regexp" do
      assert_equal(
        ".\\QFoo\\E.|\\QBar\\E.*\\QBAZ\\E",
        Util.wildcardToRegexp(java.util.Arrays.asList("_Foo_", "Bar%BAZ"))
      )
    end

    # Java: UtilTestCase#testCamel
    it "converts camelCase to UPPER_CASE" do
      assert_equal "FOO_BAR", Util.camelToUpper("FooBar")
      assert_equal "FOO_BAR", Util.camelToUpper("fooBar")
      assert_equal "URL", Util.camelToUpper("URL")
      assert_equal "URLTO_CLICK_ON", Util.camelToUpper("URLtoClickOn")
      assert_equal "", Util.camelToUpper("")
    end
  end

  describe "comma list parsing" do
    # Java: UtilTestCase#testParseCommaList
    it "parses comma-separated lists" do
      assert_equal java.util.ArrayList.new, Util.parseCommaList("")
      assert_equal java.util.Arrays.asList("x"), Util.parseCommaList("x")
      assert_equal java.util.Arrays.asList("x", "y"), Util.parseCommaList("x,y")
      assert_equal java.util.Arrays.asList("x,y"), Util.parseCommaList("x,,y")
      assert_equal java.util.Arrays.asList(",x", "y"), Util.parseCommaList(",,x,y")
      assert_equal java.util.Arrays.asList("x,", "y"), Util.parseCommaList("x,,,y")
      assert_equal java.util.Arrays.asList("x,,y"), Util.parseCommaList("x,,,,y")
      # ignore trailing comma
      assert_equal java.util.Arrays.asList("x", "y"), Util.parseCommaList("x,y,")
      assert_equal java.util.Arrays.asList("x", "y,"), Util.parseCommaList("x,y,,")
    end
  end

  describe "iterators and iterables" do
    # Java: UtilTestCase#testUnionIterator
    it "iterates over union of multiple lists" do
      xy_list = java.util.Arrays.asList("x", "y")
      abc_list = java.util.Arrays.asList("a", "b", "c")
      empty_list = java.util.Collections.emptyList

      total = ""
      Java::MondrianUtil::UnionIterator.over(xy_list, abc_list).each { |s| total += "#{s};" }
      assert_equal "x;y;a;b;c;", total

      total = ""
      Java::MondrianUtil::UnionIterator.over(xy_list, empty_list).each { |s| total += "#{s};" }
      assert_equal "x;y;", total

      total = ""
      Java::MondrianUtil::UnionIterator.over(empty_list, xy_list, empty_list).each { |s| total += "#{s};" }
      assert_equal "x;y;", total

      total = ""
      Java::MondrianUtil::UnionIterator.over.each { |s| total += "#{s};" }
      assert_equal "", total

      total = ""
      union_iterator = Java::MondrianUtil::UnionIterator.new(xy_list, abc_list)
      while union_iterator.hasNext
        total += "#{union_iterator.next};"
      end
      assert_equal "x;y;a;b;c;", total

      unless Util::Retrowoven
        total = ""
        Java::MondrianUtil::UnionIterator.over(xy_list, abc_list).each { |s| total += "#{s};" }
        assert_equal "x;y;a;b;c;", total
      end
    end

    # Java: UtilTestCase#testCompositeIterable
    it "iterates over composite iterables" do
      beatles = java.util.Arrays.asList("john", "paul", "george", "ringo")
      stones = java.util.Arrays.asList("mick", "keef", "brian", "bill", "charlie")
      empty = java.util.Collections.emptyList

      result = ""
      Java::MondrianUtil::Composite.of(beatles, stones).each { |s| result += "#{s};" }
      assert_equal "john;paul;george;ringo;mick;keef;brian;bill;charlie;", result

      result = ""
      Java::MondrianUtil::Composite.of(empty, stones).each { |s| result += "#{s};" }
      assert_equal "mick;keef;brian;bill;charlie;", result

      result = ""
      Java::MondrianUtil::Composite.of(stones, empty).each { |s| result += "#{s};" }
      assert_equal "mick;keef;brian;bill;charlie;", result

      result = ""
      Java::MondrianUtil::Composite.of(empty).each { |s| result += "#{s};" }
      assert_equal "", result

      result = ""
      Java::MondrianUtil::Composite.of(empty, empty, beatles, empty, empty).each { |s| result += "#{s};" }
      assert_equal "john;paul;george;ringo;", result
    end
  end

  describe "collection utilities" do
    # Java: UtilTestCase#testAreOccurrencesEqual
    it "checks if all occurrences are equal" do
      assert_equal false, Util.areOccurencesEqual(java.util.Collections.emptyList)
      assert_equal true, Util.areOccurencesEqual(java.util.Arrays.asList("x"))
      assert_equal true, Util.areOccurencesEqual(java.util.Arrays.asList("x", "x"))
      assert_equal false, Util.areOccurencesEqual(java.util.Arrays.asList("x", "y"))
      assert_equal false, Util.areOccurencesEqual(java.util.Arrays.asList("x", "y", "x"))
      assert_equal true, Util.areOccurencesEqual(java.util.Arrays.asList("x", "x", "x"))
      assert_equal false, Util.areOccurencesEqual(java.util.Arrays.asList("x", "x", "y", "z"))
    end

    # Java: UtilTestCase#testCanCast
    # JRuby boxes Ruby integers as Long, so we use explicit Java Integer/Double objects
    # where the Java test uses int/double literals
    it "checks if collection can be cast to a type" do
      int1 = java.lang.Integer.new(1)
      int2 = java.lang.Integer.new(2)
      dbl2 = java.lang.Double.new(2.0)

      assert_equal true, Util.canCast(java.util.Collections::EMPTY_LIST, java.lang.Integer.java_class)
      assert_equal true, Util.canCast(java.util.Collections::EMPTY_LIST, java.lang.String.java_class)
      assert_equal true, Util.canCast(java.util.Collections::EMPTY_SET, java.lang.String.java_class)
      assert_equal true, Util.canCast(java.util.Arrays.asList(int1, int2), java.lang.Integer.java_class)
      assert_equal true, Util.canCast(java.util.Arrays.asList(int1, int2), java.lang.Number.java_class)
      assert_equal false, Util.canCast(java.util.Arrays.asList(int1, int2), java.lang.String.java_class)
      assert_equal true, Util.canCast(java.util.Arrays.asList(int1, nil, dbl2), java.lang.Number.java_class)
      hash_set = java.util.HashSet.new(java.util.Arrays.asList(int1, nil, dbl2))
      assert_equal true, Util.canCast(hash_set, java.lang.Number.java_class)
      assert_equal false, Util.canCast(java.util.Arrays.asList(int1, nil, dbl2), java.lang.Integer.java_class)
    end
  end

  describe "service discovery" do
    # Java: UtilTestCase#testServiceDiscovery
    it "discovers JDBC driver services" do
      service_discovery = Java::MondrianUtil::ServiceDiscovery.forClass(java.sql.Driver.java_class)
      list = service_discovery.getImplementor
      refute list.isEmpty

      expected_class_names = java.util.ArrayList.new(
        java.util.Arrays.asList(
          "mondrian.olap4j.MondrianOlap4jDriver"
        )
      )
      list.each do |driver_class|
        expected_class_names.remove(driver_class.getName)
      end
      assert expected_class_names.isEmpty, expected_class_names.toString
    end
  end

  describe "data structures" do
    # Java: UtilTestCase#testArrayStack
    it "ArrayStack push/pop/peek operations" do
      stack = Java::MondrianUtil::ArrayStack.new
      assert_equal 0, stack.size
      stack.add("a")
      assert_equal 1, stack.size
      assert_equal "a", stack.peek
      stack.push("b")
      assert_equal 2, stack.size
      assert_equal "b", stack.peek
      assert_equal "b", stack.pop
      assert_equal 1, stack.size
      stack.add(0, "z")
      assert_equal "a", stack.peek
      assert_equal 2, stack.size
      stack.push(nil)
      assert_equal 3, stack.size
      assert_equal java.util.Arrays.asList("z", "a", nil), stack

      result = ""
      stack.each { |s| result += s.nil? ? "null" : s.to_s }
      assert_equal "zanull", result

      stack.clear
      assert_raises(java.util.EmptyStackException) { stack.peek }
      assert_raises(java.util.EmptyStackException) { stack.pop }
    end

    # Java: UtilTestCase#testAppendArrays
    # JRuby cannot resolve T[]... varargs for array arguments automatically,
    # so we wrap rest args in an explicit typed array
    it "appends arrays" do
      a0 = ["a", "b", "c"].to_java(:string)
      a1 = ["foo", "bar"].to_java(:string)
      empty = [].to_java(:string)

      strings1 = Util.appendArrays(a0, [a1].to_java(java.lang.String[]))
      assert_equal 5, strings1.length
      assert_equal java.util.Arrays.asList("a", "b", "c", "foo", "bar"), java.util.Arrays.asList(strings1)

      strings2 = Util.appendArrays(empty, [a0, empty, a1, empty].to_java(java.lang.String[]))
      assert_equal java.util.Arrays.asList("a", "b", "c", "foo", "bar"), java.util.Arrays.asList(strings2)

      n0 = [java.lang.Math::PI].to_java(java.lang.Number)
      i0 = [java.lang.Integer.new(123), nil, java.lang.Integer.new(45)].to_java(java.lang.Number)
      f0 = [java.lang.Float.new(0.0)].to_java(java.lang.Number)

      numbers = Util.appendArrays(n0, [i0, f0].to_java(java.lang.Number[]))
      assert_equal 5, numbers.length
      assert_equal(
        java.util.Arrays.asList(
          java.lang.Math::PI, java.lang.Integer.new(123), nil, java.lang.Integer.new(45), java.lang.Float.new(0.0)
        ),
        java.util.Arrays.asList(numbers)
      )
    end

    # Java: UtilTestCase#testParseLocale
    it "parses locale strings" do
      locales = [
        java.util.Locale::CANADA,
        java.util.Locale::CANADA_FRENCH,
        java.util.Locale.getDefault,
        java.util.Locale::US,
        java.util.Locale::TRADITIONAL_CHINESE,
      ]
      locales.each do |locale|
        assert_equal locale, Util.parseLocale(locale.toString)
      end

      locale_names = %w[en de_DE _GB en_US_WIN de__POSIX fr__MAC]
      locale_names.each do |locale_name|
        assert_equal locale_name, Util.parseLocale(locale_name).toString
      end
    end

    # Java: UtilTestCase#testLockBox
    # Uses Java objects that JRuby does not auto-convert, so assert_same verifies
    # true object identity. In production LockBox stores Role objects (not Strings).
    it "LockBox register/deregister/get with object identity" do
      box = Java::MondrianUtil::LockBox.new

      abc = java.util.ArrayList.new(java.util.Arrays.asList("a", "b", "c"))
      xy = java.util.ArrayList.new(java.util.Arrays.asList("x", "y"))

      # Register an object
      abc_entry0 = box.register(abc)
      refute_nil abc_entry0
      assert_same abc, abc_entry0.getValue
      check_moniker_valid(abc_entry0.getMoniker)

      # Register another object
      xy_entry = box.register(xy)
      check_moniker_valid(xy_entry.getMoniker)
      refute_equal abc_entry0.getMoniker, xy_entry.getMoniker

      # Register first object again — different moniker, different registration
      abc_entry1 = box.register(abc)
      check_moniker_valid(abc_entry1.getMoniker)
      refute_equal abc_entry0.getMoniker, abc_entry1.getMoniker
      assert_same abc, abc_entry1.getValue

      # Retrieve
      abc_entry0b = box.get(abc_entry0.getMoniker)
      refute_nil abc_entry0b
      assert_equal abc_entry0.getMoniker, abc_entry0b.getMoniker
      assert_same abc_entry0, abc_entry0b
      refute_same abc_entry0b, abc_entry1
      refute_equal abc_entry1.getMoniker, abc_entry0b.getMoniker

      # Arbitrary moniker retrieves nothing
      assert_nil box.get("xxx")

      # Deregister
      assert_equal true, abc_entry0b.isRegistered
      assert_equal true, box.deregister(abc_entry0b)
      assert_equal false, abc_entry0b.isRegistered
      assert_nil box.get(abc_entry0.getMoniker)

      # The other entry created by the same call to 'register' is also deregistered
      assert_equal false, abc_entry0.isRegistered
      assert_equal true, abc_entry1.isRegistered

      # Deregister again
      assert_equal false, box.deregister(abc_entry0b)
      assert_equal false, abc_entry0b.isRegistered
      assert_equal false, abc_entry0.isRegistered
      assert_nil box.get(abc_entry0.getMoniker)

      # Entry is no longer registered, therefore cannot get value
      error = assert_raises(java.lang.RuntimeException) do
        abc_entry0.getValue
      end
      assert error.message.start_with?("LockBox has no entry with moniker")
      refute_nil abc_entry0.getMoniker

      # Other registration of same object still works
      abc_entry1b = box.get(abc_entry1.getMoniker)
      refute_nil abc_entry1b
      assert_same abc_entry1, abc_entry1b
      assert_same abc, abc_entry1b.getValue
      assert_same abc, abc_entry1.getValue

      # Other entry still exists
      xy_entry2 = box.get(xy_entry.getMoniker)
      refute_nil xy_entry2
      assert_same xy_entry, xy_entry2
      assert_same xy, xy_entry2.getValue
      assert_same xy, xy_entry.getValue

      # Register again — moniker is different (never recycled)
      abc_entry3 = box.register(abc)
      check_moniker_valid(abc_entry3.getMoniker)
      refute_equal abc_entry0.getMoniker, abc_entry3.getMoniker
      refute_equal abc_entry1.getMoniker, abc_entry3.getMoniker
      refute_equal abc_entry0b.getMoniker, abc_entry3.getMoniker

      # Previous entry is no longer valid
      assert_equal true, abc_entry1.isRegistered
      assert_equal false, abc_entry0.isRegistered
    end

    # Java: UtilTestCase#testLockBox
    # Same test with Strings matching the original Java test. JRuby auto-converts
    # java.lang.String returns to Ruby Strings, so assert_equal is used for values.
    it "LockBox register/deregister/get with strings" do
      box = Java::MondrianUtil::LockBox.new

      abc = "abc"
      xy = "xy"

      # Register an object
      abc_entry0 = box.register(abc)
      refute_nil abc_entry0
      assert_equal abc, abc_entry0.getValue
      check_moniker_valid(abc_entry0.getMoniker)

      # Register another object
      xy_entry = box.register(xy)
      check_moniker_valid(xy_entry.getMoniker)
      refute_equal abc_entry0.getMoniker, xy_entry.getMoniker

      # Register first object again — different moniker, different registration
      abc_entry1 = box.register(abc)
      check_moniker_valid(abc_entry1.getMoniker)
      refute_equal abc_entry0.getMoniker, abc_entry1.getMoniker
      assert_equal abc, abc_entry1.getValue

      # Retrieve
      abc_entry0b = box.get(abc_entry0.getMoniker)
      refute_nil abc_entry0b
      assert_equal abc_entry0.getMoniker, abc_entry0b.getMoniker
      assert_same abc_entry0, abc_entry0b
      refute_same abc_entry0b, abc_entry1
      refute_equal abc_entry1.getMoniker, abc_entry0b.getMoniker

      # Arbitrary moniker retrieves nothing
      assert_nil box.get("xxx")

      # Deregister
      assert_equal true, abc_entry0b.isRegistered
      assert_equal true, box.deregister(abc_entry0b)
      assert_equal false, abc_entry0b.isRegistered
      assert_nil box.get(abc_entry0.getMoniker)

      # The other entry created by the same call to 'register' is also deregistered
      assert_equal false, abc_entry0.isRegistered
      assert_equal true, abc_entry1.isRegistered

      # Deregister again
      assert_equal false, box.deregister(abc_entry0b)
      assert_equal false, abc_entry0b.isRegistered
      assert_equal false, abc_entry0.isRegistered
      assert_nil box.get(abc_entry0.getMoniker)

      # Entry is no longer registered, therefore cannot get value
      error = assert_raises(java.lang.RuntimeException) do
        abc_entry0.getValue
      end
      assert error.message.start_with?("LockBox has no entry with moniker")
      refute_nil abc_entry0.getMoniker

      # Other registration of same object still works
      abc_entry1b = box.get(abc_entry1.getMoniker)
      refute_nil abc_entry1b
      assert_same abc_entry1, abc_entry1b
      assert_equal abc, abc_entry1b.getValue
      assert_equal abc, abc_entry1.getValue

      # Other entry still exists
      xy_entry2 = box.get(xy_entry.getMoniker)
      refute_nil xy_entry2
      assert_same xy_entry, xy_entry2
      assert_equal xy, xy_entry2.getValue
      assert_equal xy, xy_entry.getValue

      # Register again — moniker is different (never recycled)
      abc_entry3 = box.register(abc)
      check_moniker_valid(abc_entry3.getMoniker)
      refute_equal abc_entry0.getMoniker, abc_entry3.getMoniker
      refute_equal abc_entry1.getMoniker, abc_entry3.getMoniker
      refute_equal abc_entry0b.getMoniker, abc_entry3.getMoniker

      # Previous entry is no longer valid
      assert_equal true, abc_entry1.isRegistered
      assert_equal false, abc_entry0.isRegistered
    end

    # Java: UtilTestCase#testLockBoxFull
    it "LockBox handles large number of entries with GC" do
      box = Java::MondrianUtil::LockBox.new
      base = "x" * 10_000

      max = 1_000_000
      entries = Array.new(567)
      max.times do |i|
        value = "#{base}#{i}"

        entry = box.register(value)
        entries[i % entries.length] = entry
        refute_nil entries[[i, (i * 19) % 567].min].getValue
      end
    end

    # Java: UtilTestCase#testCartesianProductList
    it "CartesianProductList computes correct products" do
      list = Java::MondrianUtil::CartesianProductList.new(
        java.util.Arrays.asList(
          java.util.Arrays.asList("a", "b"),
          java.util.Arrays.asList("1", "2", "3")
        )
      )
      assert_equal 6, list.size
      assert_equal false, list.isEmpty
      check_cartesian_list_contents(list)
      assert_equal "[[a, 1], [a, 2], [a, 3], [b, 1], [b, 2], [b, 3]]", list.toString

      # One element empty
      list2 = Java::MondrianUtil::CartesianProductList.new(
        java.util.Arrays.asList(
          java.util.Arrays.asList,
          java.util.Arrays.asList("1", "2", "3")
        )
      )
      assert_equal true, list2.isEmpty
      assert_equal "[]", list2.toString
      check_cartesian_list_contents(list2)

      # Other component empty
      list3 = Java::MondrianUtil::CartesianProductList.new(
        java.util.Arrays.asList(
          java.util.Arrays.asList("a", "b"),
          java.util.Arrays.asList
        )
      )
      assert_equal true, list3.isEmpty
      assert_equal "[]", list3.toString
      check_cartesian_list_contents(list3)

      # Zeroary
      list4 = Java::MondrianUtil::CartesianProductList.new(java.util.Collections.emptyList)
      assert_equal false, list4.isEmpty
      check_cartesian_list_contents(list4)

      # 1-ary
      list5 = Java::MondrianUtil::CartesianProductList.new(
        java.util.Collections.singletonList(java.util.Arrays.asList("a", "b"))
      )
      assert_equal "[[a], [b]]", list5.toString
      check_cartesian_list_contents(list5)

      # 3-ary
      list6 = Java::MondrianUtil::CartesianProductList.new(
        java.util.Arrays.asList(
          java.util.Arrays.asList("a", "b", "c", "d"),
          java.util.Arrays.asList("1", "2"),
          java.util.Arrays.asList("x", "y", "z")
        )
      )
      assert_equal 24, list6.size
      assert_equal false, list6.isEmpty
      assert_equal "[a, 1, x]", list6.get(0).toString
      assert_equal "[a, 1, y]", list6.get(1).toString
      assert_equal "[d, 2, z]", list6.get(23).toString
      check_cartesian_list_contents(list6)

      strings = java.lang.Object[6].new
      list6.getIntoArray(1, strings)
      assert_equal "[a, 1, y, null, null, null]", java.util.Arrays.asList(strings).toString

      list7 = Java::MondrianUtil::CartesianProductList.new(
        java.util.Arrays.asList(
          java.util.Arrays.asList(
            "1",
            java.util.Arrays.asList("2a", nil, "2c"),
            "3"
          ),
          java.util.Arrays.asList(
            "a",
            java.util.Arrays.asList("bb", "bbb"),
            "c",
            "d"
          )
        )
      )
      list7.getIntoArray(1, strings)
      assert_equal "[1, bb, bbb, null, null, null]", java.util.Arrays.asList(strings).toString
      list7.getIntoArray(5, strings)
      assert_equal "[2a, null, 2c, bb, bbb, null]", java.util.Arrays.asList(strings).toString
      check_cartesian_list_contents(list7)
    end

    # Java: UtilTestCase#testFlatList
    it "FlatList equality and hashCode" do
      flat_ab = Util.flatList("a", "b")
      array_ab = java.util.Arrays.asList("a", "b")
      assert_equal flat_ab, flat_ab
      assert_equal flat_ab, array_ab
      assert_equal array_ab, flat_ab
      assert_equal array_ab.hashCode, flat_ab.hashCode

      flat_abc = Util.flatList("a", "b", "c")
      array_abc = java.util.Arrays.asList("a", "b", "c")
      assert_equal flat_abc, flat_abc
      assert_equal flat_abc, array_abc
      assert_equal array_abc, flat_abc
      assert_equal array_abc.hashCode, flat_abc.hashCode

      assert_equal "[a, b, c]", flat_abc.toString
      assert_equal "[a, b]", flat_ab.toString

      array_empty = java.util.Arrays.asList
      array_a = java.util.Collections.singletonList("a")

      # mixed 2 & 3
      [array_empty, array_a, array_abc, flat_abc].each do |strings|
        assert_equal false, strings.equals(flat_ab)
        assert_equal false, flat_ab.equals(strings)
      end
      [array_empty, array_a, array_ab, flat_ab].each do |strings|
        assert_equal false, strings.equals(flat_abc)
        assert_equal false, flat_abc.equals(strings)
      end
    end

    # Java: UtilTestCase#testCombiningGenerator
    it "CombiningGenerator produces correct combinations" do
      assert_equal 1, Java::MondrianUtil::CombiningGenerator.new(java.util.Collections.emptyList).size
      assert_equal 1, Java::MondrianUtil::CombiningGenerator.of(java.util.Collections.emptyList).size
      assert_equal "[[]]", Java::MondrianUtil::CombiningGenerator.of(java.util.Collections.emptyList).toString
      assert_equal "[[], [a]]", Java::MondrianUtil::CombiningGenerator.of(java.util.Collections.singletonList("a")).toString
      assert_equal "[[], [a], [b], [a, b]]", Java::MondrianUtil::CombiningGenerator.of(java.util.Arrays.asList("a", "b")).toString
      assert_equal(
        "[[], [a], [b], [a, b], [c], [a, c], [b, c], [a, b, c]]",
        Java::MondrianUtil::CombiningGenerator.of(java.util.Arrays.asList("a", "b", "c")).toString
      )

      integer_list = java.util.Arrays.asList(0, 1, 2, 3, 4, 5, 6, 7, 8)
      i = 0
      Java::MondrianUtil::CombiningGenerator.of(integer_list).each do |integers|
        case i
        when 0 then assert_equal true, integers.isEmpty
        when 1 then assert_equal java.util.Arrays.asList(0), integers
        when 6 then assert_equal java.util.Arrays.asList(1, 2), integers
        when 131 then assert_equal java.util.Arrays.asList(0, 1, 7), integers
        end
        i += 1
      end
      assert_equal 512, i

      # Check that can iterate over 2^20 (~ 1m) elements in reasonable time
      i = 0
      Java::MondrianUtil::CombiningGenerator.of(java.util.Collections.nCopies(20, "x")).each do |xx|
        Util.discard(xx)
        i += 1
      end
      assert_equal 1 << 20, i
    end

    # Java: UtilTestCase#testByteString
    it "ByteString equality, hashCode, compareTo, and toString" do
      empty0 = Java::MondrianUtil::ByteString.new([].to_java(:byte))
      empty1 = Java::MondrianUtil::ByteString.new([].to_java(:byte))
      assert_equal true, empty0.equals(empty1)
      assert_equal empty0.hashCode, empty1.hashCode
      assert_equal "", empty0.toString
      assert_equal 0, empty0.length
      assert_equal 0, empty0.compareTo(empty0)
      assert_equal 0, empty0.compareTo(empty1)

      two = Java::MondrianUtil::ByteString.new([0xDE, 0xAD].pack("C*").to_java_bytes)
      assert_equal false, empty0.equals(two)
      assert_equal false, two.equals(empty0)
      assert_equal "dead", two.toString
      assert_equal 2, two.length
      assert_equal 0, two.compareTo(two)
      assert(empty0.compareTo(two) < 0)
      assert(two.compareTo(empty0) > 0)

      three = Java::MondrianUtil::ByteString.new([0xDE, 0x02, 0xAD].pack("C*").to_java_bytes)
      assert_equal 3, three.length
      assert_equal "de02ad", three.toString
      assert(two.compareTo(three) < 0)
      assert(three.compareTo(two) > 0)
      assert_equal 0x02, three.byteAt(1)

      set = java.util.HashSet.new
      set.addAll(java.util.Arrays.asList(empty0, two, three, two, empty1, three))
      assert_equal 3, set.size
    end

    # Java: UtilTestCase#testBinarySearch
    it "binary search finds correct indices" do
      abce = ["a", "b", "c", "e"].to_java(java.lang.Comparable)
      assert_equal 0, Util.binarySearch(abce, 0, 4, "a")
      assert_equal 1, Util.binarySearch(abce, 0, 4, "b")
      assert_equal 1, Util.binarySearch(abce, 1, 4, "b")
      assert_equal(-4, Util.binarySearch(abce, 0, 4, "d"))
      assert_equal(-4, Util.binarySearch(abce, 1, 4, "d"))
      assert_equal(-4, Util.binarySearch(abce, 2, 4, "d"))
      assert_equal(-4, Util.binarySearch(abce, 2, 3, "d"))
      assert_equal(-4, Util.binarySearch(abce, 2, 3, "e"))
      assert_equal(-4, Util.binarySearch(abce, 2, 3, "f"))
      assert_equal(-5, Util.binarySearch(abce, 0, 4, "f"))
      assert_equal(-5, Util.binarySearch(abce, 2, 4, "f"))
    end

    # Java: UtilTestCase#testArraySortedSet
    it "ArraySortedSet operations" do
      abce = ["a", "b", "c", "e"].to_java(:string)
      abce_set = Java::MondrianUtil::ArraySortedSet.new(abce)

      assert_equal 4, abce_set.size
      assert_equal false, abce_set.isEmpty
      assert_equal "a", abce_set.first
      assert_equal "e", abce_set.last
      assert_equal true, abce_set.contains("a")
      assert_equal false, abce_set.contains("aa")
      assert_equal false, abce_set.contains("z")
      assert_equal false, abce_set.contains(nil)
      check_to_string("[a, b, c, e]", abce_set)

      # test iterator
      result = ""
      abce_set.each { |s| result += "#{s};" }
      assert_equal "a;b;c;e;", result

      # empty set
      empty_set = Java::MondrianUtil::ArraySortedSet.new([].to_java(:string))
      count = 0
      empty_set.each { count += 1 }
      assert_equal 0, count
      assert_equal 0, empty_set.size
      assert_equal true, empty_set.isEmpty
      assert_raises(java.util.NoSuchElementException) { empty_set.first }
      assert_raises(java.util.NoSuchElementException) { empty_set.last }
      assert_equal false, empty_set.contains("a")
      assert_equal false, empty_set.contains("aa")
      assert_equal false, empty_set.contains("z")
      check_to_string("[]", empty_set)

      # same hashCode etc. as similar hashset
      abc_hashset = java.util.HashSet.new
      abc_hashset.addAll(java.util.Arrays.asList(abce))
      assert_equal abc_hashset, abce_set
      assert_equal abce_set, abc_hashset
      assert_equal abce_set.hashCode, abc_hashset.hashCode

      # subset to end
      subset_end = Java::MondrianUtil::ArraySortedSet.new(abce, 1, 4)
      check_to_string("[b, c, e]", subset_end)
      assert_equal 3, subset_end.size
      assert_equal false, subset_end.isEmpty
      assert_equal true, subset_end.contains("c")
      assert_equal false, subset_end.contains("a")
      assert_equal false, subset_end.contains("z")

      # subset from start
      subset_start = Java::MondrianUtil::ArraySortedSet.new(abce, 0, 2)
      check_to_string("[a, b]", subset_start)
      assert_equal 2, subset_start.size
      assert_equal false, subset_start.isEmpty
      assert_equal true, subset_start.contains("a")
      assert_equal false, subset_start.contains("c")

      # subset from neither start nor end
      subset = Java::MondrianUtil::ArraySortedSet.new(abce, 1, 2)
      check_to_string("[b]", subset)
      assert_equal 1, subset.size
      assert_equal false, subset.isEmpty
      assert_equal true, subset.contains("b")
      assert_equal false, subset.contains("a")
      assert_equal false, subset.contains("e")

      # empty subset
      subset_empty = Java::MondrianUtil::ArraySortedSet.new(abce, 1, 1)
      check_to_string("[]", subset_empty)
      assert_equal 0, subset_empty.size
      assert_equal true, subset_empty.isEmpty
      assert_equal false, subset_empty.contains("e")

      # subsets based on elements, not ordinals
      assert_equal abce_set.subSet("a", "c"), subset_start
      assert_equal "[a, b, c]", abce_set.subSet("a", "d").toString
      assert_equal false, abce_set.subSet("a", "e").equals(subset_start)
      assert_equal false, abce_set.subSet("b", "c").equals(subset_start)
      assert_equal "[c, e]", abce_set.subSet("c", "z").toString
      assert_equal "[e]", abce_set.subSet("d", "z").toString
      assert_equal false, abce_set.subSet("e", "c").equals(subset_start)
      assert_equal "[]", abce_set.subSet("e", "c").toString
      assert_equal false, abce_set.subSet("z", "c").equals(subset_start)
      assert_equal "[]", abce_set.subSet("z", "c").toString

      # merge
      ar1 = Java::MondrianUtil::ArraySortedSet.new(abce)
      ar2 = Java::MondrianUtil::ArraySortedSet.new(["d"].to_java(:string))
      ar3 = Java::MondrianUtil::ArraySortedSet.new(["b", "c"].to_java(:string))
      check_to_string("[a, b, c, e]", ar1)
      check_to_string("[d]", ar2)
      check_to_string("[b, c]", ar3)
      check_to_string("[a, b, c, d, e]", ar1.merge(ar2))
      check_to_string("[a, b, c, e]", ar1.merge(ar3))
    end

    # Java: UtilTestCase#testIntersectSortedSet
    it "intersects sorted sets" do
      ace = Java::MondrianUtil::ArraySortedSet.new(["a", "c", "e"].to_java(:string))
      cd = Java::MondrianUtil::ArraySortedSet.new(["c", "d"].to_java(:string))
      bdf = Java::MondrianUtil::ArraySortedSet.new(["b", "d", "f"].to_java(:string))
      bde = Java::MondrianUtil::ArraySortedSet.new(["b", "d", "e"].to_java(:string))
      empty = Java::MondrianUtil::ArraySortedSet.new([].to_java(:string))

      check_to_string("[a, c, e]", Util.intersect(ace, ace))
      check_to_string("[c]", Util.intersect(ace, cd))
      check_to_string("[]", Util.intersect(ace, empty))
      check_to_string("[]", Util.intersect(empty, ace))
      check_to_string("[]", Util.intersect(empty, empty))
      check_to_string("[]", Util.intersect(ace, bdf))
      check_to_string("[e]", Util.intersect(ace, bde))
    end

    # Java: UtilTestCase#testTriple
    it "Triple equality, hashCode, compareTo, and toString" do
      triple0 = Java::MondrianUtil::Triple.of(5, "foo", true)
      triple1 = Java::MondrianUtil::Triple.of(5, "foo", false)
      triple2 = Java::MondrianUtil::Triple.of(5, "foo", true)
      triple3 = Java::MondrianUtil::Triple.of(nil, "foo", true)

      assert_equal triple0, triple0
      assert_equal false, triple0.equals(triple1)
      assert_equal false, triple1.equals(triple0)
      refute_equal triple0.hashCode, triple1.hashCode
      assert_equal triple0, triple2
      assert_equal triple0.hashCode, triple2.hashCode
      assert_equal triple3, triple3
      assert_equal false, triple0.equals(triple3)
      assert_equal false, triple3.equals(triple0)
      refute_equal triple0.hashCode, triple3.hashCode

      set = java.util.TreeSet.new(
        java.util.Arrays.asList(triple0, triple1, triple2, triple3, triple1)
      )
      assert_equal 3, set.size
      assert_equal "[<null, foo, true>, <5, foo, false>, <5, foo, true>]", set.toString

      assert_equal "<5, foo, true>", triple0.toString
      assert_equal "<5, foo, false>", triple1.toString
      assert_equal "<5, foo, true>", triple2.toString
      assert_equal "<null, foo, true>", triple3.toString
    end
  end

  describe "RolapUtil" do
    # Java: UtilTestCase#testRolapUtilComparator
    it "binarySearch handles sqlNullValue without ClassCastException" do
      comp_array = ["1", "2", "3", "4"].to_java(java.lang.Comparable)
      # Will throw a ClassCastException if it fails
      Util.binarySearch(comp_array, 0, comp_array.length, Java::MondrianRolap::RolapUtil.sqlNullValue)
      assert true
    end
  end

  describe "ByteMatcher" do
    # Java: UtilTestCase#testByteMatcher
    it "matches byte patterns" do
      bm = Util::ByteMatcher.new([0x2A].pack("C*").to_java_bytes)
      bytes_not_present = [0x2B, 0x2C].pack("C*").to_java_bytes
      bytes_present = [0x2B, 0x2A, 0x2C].pack("C*").to_java_bytes
      bytes_present_last = [0x2B, 0x2C, 0x2A].pack("C*").to_java_bytes
      bytes_present_first = [0x2A, 0x2C, 0x2B].pack("C*").to_java_bytes

      assert_equal(-1, bm.match(bytes_not_present))
      assert_equal 1, bm.match(bytes_present)
      assert_equal 2, bm.match(bytes_present_last)
      assert_equal 0, bm.match(bytes_present_first)
    end
  end

  describe "NullValuesMap" do
    # Java: UtilTestCase#testNullValuesMap
    it "does not iterate source list upon creation" do
      throwing_list = ThrowingArrayList.new(java.util.Arrays.asList("CHUNKY", "BACON!!"))
      null_values_map = Util.toNullValuesMap(throwing_list)

      # This should fail — triggers iteration
      assert_raises(java.lang.RuntimeException) do
        null_values_map.entrySet.iterator.next
      end

      # None of the above operations should trigger iteration
      assert_equal false, null_values_map.entrySet.isEmpty
      assert_equal true, null_values_map.containsKey("CHUNKY")
      assert_equal true, null_values_map.containsValue(nil)
      assert_equal false, null_values_map.containsKey(nil)
      assert_equal false, null_values_map.keySet.contains("Something")
    end
  end

  describe "parseInterval" do
    Pair = Java::MondrianUtil::Pair
    TimeUnit = java.util.concurrent.TimeUnit

    # Java: UtilTestCase#testParseInterval
    it "parses time intervals" do
      # no default unit
      assert_equal Pair.of(1, TimeUnit::SECONDS), Util.parseInterval("1s", nil)
      # same default unit as actual
      assert_equal Pair.of(1, TimeUnit::SECONDS), Util.parseInterval("1s", TimeUnit::SECONDS)
      # different default than actual
      assert_equal Pair.of(1, TimeUnit::SECONDS), Util.parseInterval("1s", TimeUnit::MILLISECONDS)
      assert_equal Pair.of(2, TimeUnit::NANOSECONDS), Util.parseInterval("2ns", TimeUnit::MICROSECONDS)

      # each unit in turn
      assert_equal Pair.of(5, TimeUnit::NANOSECONDS), Util.parseInterval("5ns", nil)
      assert_equal Pair.of(3, TimeUnit::MICROSECONDS), Util.parseInterval("3us", nil)
      assert_equal Pair.of(4, TimeUnit::MILLISECONDS), Util.parseInterval("4ms", nil)
      assert_equal Pair.of(5, TimeUnit.valueOf("MINUTES")), Util.parseInterval("5m", nil)
      assert_equal Pair.of(6, TimeUnit.valueOf("HOURS")), Util.parseInterval("6h", nil)
      assert_equal Pair.of(7, TimeUnit.valueOf("DAYS")), Util.parseInterval("7d", nil)

      # negative
      assert_equal Pair.of(-8, TimeUnit::SECONDS), Util.parseInterval("-8s", nil)

      # default unit used when none specified
      assert_equal Pair.of(3, TimeUnit::MICROSECONDS), Util.parseInterval("3", TimeUnit::MICROSECONDS)

      # no unit and no default — error
      error = assert_raises(java.lang.NumberFormatException) do
        Util.parseInterval("4", nil)
      end
      assert error.message.start_with?("Invalid time interval '4'. Does not contain a time unit.")

      # fractional part rounded away
      assert_equal Pair.of(1234, TimeUnit::SECONDS), Util.parseInterval("1234.567s", TimeUnit::MICROSECONDS)

      # Invalid unit ('S' is not valid for 's')
      error = assert_raises(java.lang.NumberFormatException) do
        Util.parseInterval("40S", nil)
      end
      assert error.message.start_with?("Invalid time interval '40S'. Does not contain a time unit.")

      # Space is not allowed
      error = assert_raises(java.lang.NumberFormatException) do
        Util.parseInterval("40 m", nil)
      end
      assert error.message.start_with?("Invalid time interval '40 m'")

      # Two time units
      error = assert_raises(java.lang.NumberFormatException) do
        Util.parseInterval("40sms", nil)
      end
      assert error.message.start_with?("Invalid time interval '40sms'")

      # Null
      assert_raises(java.lang.NullPointerException) do
        Util.parseInterval(nil, nil)
      end
    end
  end
end
