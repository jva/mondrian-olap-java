# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2005-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

CellKey = Java::MondrianRolap::CellKey

# Java: mondrian/rolap/CellKeyTest.java
describe "CellKey" do
  # Java original used a boolean flag + assertTrue; assert_raises is stricter but holds.
  def assert_cell_key_exception(key, action_description)
    assert_raises(Java::JavaLang::Exception, "CellKey #{action_description}") do
      yield
    end
  end

  describe "many-dimensional key" do
    # Java: CellKeyTest#testMany
    it "supports copy, equality, ordinals, and boundary exceptions for 5-axis key" do
      key = CellKey::Generator.newCellKey(5)

      assert_equal 5, key.size

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)

      assert_cell_key_exception(key, "axis too big") { key.setAxis(6, 1) }
      assert_cell_key_exception(key, "array too big") { key.setOrdinals([0, 0, 0, 0, 0, 0].to_java(:int)) }
      assert_cell_key_exception(key, "array too small") { key.setOrdinals([0, 0, 0, 0].to_java(:int)) }

      key.setAxis(0, 1)
      key.setAxis(1, 3)
      key.setAxis(2, 5)
      key.setAxis(3, 7)
      key.setAxis(4, 13)
      assert_equal false, key.equals(copy)

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)
    end
  end

  describe "zero-dimensional key" do
    # Java: CellKeyTest#testZero
    it "returns singleton, supports copy, and rejects setAxis" do
      key = CellKey::Generator.newCellKey([].to_java(:int))
      key2 = CellKey::Generator.newCellKey([].to_java(:int))
      assert_same key, key2

      assert_equal 0, key.size

      copy = key.copy
      assert_equal copy, key

      assert_cell_key_exception(key, "axis too big") { key.setAxis(0, 0) }

      ordinals = key.getOrdinals
      assert_equal 0, ordinals.length
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)
    end
  end

  describe "one-dimensional key" do
    # Java: CellKeyTest#testOne
    it "supports copy, equality, ordinals, and boundary exceptions" do
      key = CellKey::Generator.newCellKey(1)
      assert_equal 1, key.size

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)

      assert_cell_key_exception(key, "axis too big") { key.setAxis(3, 1) }
      assert_cell_key_exception(key, "array too big") { key.setOrdinals([0, 0, 0].to_java(:int)) }
      assert_cell_key_exception(key, "array too small") { key.setOrdinals([].to_java(:int)) }

      key.setAxis(0, 1)

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)
    end
  end

  describe "two-dimensional key" do
    # Java: CellKeyTest#testTwo
    it "supports copy, equality, ordinals, and boundary exceptions" do
      key = CellKey::Generator.newCellKey(2)
      assert_equal 2, key.size

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)

      assert_cell_key_exception(key, "axis too big") { key.setAxis(3, 1) }
      assert_cell_key_exception(key, "array too big") { key.setOrdinals([0, 0, 0].to_java(:int)) }
      assert_cell_key_exception(key, "array too small") { key.setOrdinals([0].to_java(:int)) }

      key.setAxis(0, 1)
      key.setAxis(1, 3)

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)
    end
  end

  describe "three-dimensional key" do
    # Java: CellKeyTest#testThree
    it "supports copy, equality, ordinals, and boundary exceptions" do
      key = CellKey::Generator.newCellKey(3)
      assert_equal 3, key.size

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)

      assert_cell_key_exception(key, "axis too big") { key.setAxis(3, 1) }
      assert_cell_key_exception(key, "array too big") { key.setOrdinals([0, 0, 0, 0].to_java(:int)) }
      assert_cell_key_exception(key, "array too small") { key.setOrdinals([0].to_java(:int)) }

      key.setAxis(0, 1)
      key.setAxis(1, 3)
      key.setAxis(2, 5)

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)
    end
  end

  describe "four-dimensional key" do
    # Java: CellKeyTest#testFour
    it "supports copy, equality, ordinals, and boundary exceptions" do
      key = CellKey::Generator.newCellKey(4)
      assert_equal 4, key.size

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)

      assert_cell_key_exception(key, "axis too big") { key.setAxis(4, 1) }
      assert_cell_key_exception(key, "array too big") { key.setOrdinals([0, 0, 0, 0, 0].to_java(:int)) }
      assert_cell_key_exception(key, "array too small") { key.setOrdinals([0].to_java(:int)) }

      key.setAxis(0, 1)
      key.setAxis(1, 3)
      key.setAxis(2, 5)
      key.setAxis(3, 7)

      copy = key.copy
      assert_equal true, key.equals(copy)

      ordinals = key.getOrdinals
      copy = CellKey::Generator.newCellKey(ordinals.to_a.to_java(:int))
      assert_equal true, key.equals(copy)
    end
  end

  describe "cell lookup" do
    before(:all) do
      create_olap_connection
    end

    after(:all) do
      @olap&.close
    end

    # Java: CellKeyTest#testCellLookup
    it "looks up cells in a custom cube with null members" do
      # Guard: skip if NullMemberRepresentation is not the default "#null"
      null_representation = Java::MondrianOlap::MondrianProperties.instance.NullMemberRepresentation.get
      skip "Non-default NullMemberRepresentation: #{null_representation}" unless null_representation == "#null"

      cube_xml = <<~XML
        <Cube name="SalesTest" defaultMeasure="Unit Sales">
          <Table name="sales_fact_1997"/>
          <Dimension name="City" foreignKey="customer_id">
            <Hierarchy hasAll="true" primaryKey="customer_id">
              <Table name="customer"/>
              <Level name="city" column="city" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
          <Dimension name="Gender" foreignKey="customer_id">
            <Hierarchy hasAll="true" primaryKey="customer_id">
              <Table name="customer"/>
              <Level name="gender" column="gender" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
          <Dimension name="Address2" foreignKey="customer_id">
            <Hierarchy hasAll="true" primaryKey="customer_id">
              <Table name="customer"/>
              <Level name="addr" column="address2" uniqueMembers="true"/>
            </Hierarchy>
          </Dimension>
          <Measure name="Unit Sales" column="unit_sales" aggregator="sum" formatString="Standard"/>
        </Cube>
      XML

      # Make sure ExpandNonNative is not set. Otherwise, the query is
      # evaluated natively. For the given data set (which contains NULL
      # members), native evaluation produces results in a different order
      # from the non-native evaluation.
      with_properties(ExpandNonNative: false) do
        schema = SchemaHelper::FOODMART_SCHEMA.sub("<VirtualCube", "#{cube_xml}<VirtualCube")
        params = CONNECTION_PARAMS.merge(catalog_content: schema)
        params.delete(:catalog)
        olap = Mondrian::OLAP::Connection.create(params)
        begin
          mdx = <<~MDX
            With Set [*NATIVE_CJ_SET] as NonEmptyCrossJoin([Gender].Children, [Address2].Children)
            Select Generate([*NATIVE_CJ_SET], {([Gender].CurrentMember, [Address2].CurrentMember)}) on columns
            From [SalesTest] where ([City].[Redwood City])
          MDX

          assert_query_returns olap, mdx, <<~RESULT
            Axis #0:
            {[City].[Redwood City]}
            Axis #1:
            {[Gender].[F], [Address2].[#null]}
            {[Gender].[F], [Address2].[#2]}
            {[Gender].[F], [Address2].[Unit H103]}
            {[Gender].[M], [Address2].[#null]}
            {[Gender].[M], [Address2].[#208]}
            Row #0: 71
            Row #0: 10
            Row #0: 3
            Row #0: 52
            Row #0: 8
          RESULT
        ensure
          olap.close
        end
      end
    end
  end

  describe "size" do
    # Java: CellKeyTest#testSize
    it "returns correct size for keys of 1 to 19 dimensions" do
      (1..19).each do |i|
        assert_equal i, CellKey::Generator.newCellKey(Array.new(i, 0).to_java(:int)).size
        assert_equal i, CellKey::Generator.newCellKey(i).size
      end
    end
  end
end
