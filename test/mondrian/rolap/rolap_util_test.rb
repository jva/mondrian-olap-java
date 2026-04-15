# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2001-2005 Julian Hyde
# Copyright (C) 2005-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

RolapUtil = Java::MondrianRolap::RolapUtil
MondrianDef = Java::MondrianOlap::MondrianDef

# Concrete subclass of MondrianDef::Relation for testing non-Table relations.
# Replaces the Mockito mock from the Java test.
class StubRelation < MondrianDef::Relation
  def initialize(alias_name)
    super()
    @alias_name = alias_name
  end

  def getAlias
    @alias_name
  end

  def find(seek_alias)
    seek_alias == @alias_name ? self : nil
  end

  def displayXML(_out, _indent)
    # Not needed for this test
  end
end

# Java: mondrian/rolap/RolapUtilTest.java
describe "RolapUtil" do
  FILTER_QUERY = "`TableAlias`.`promotion_id` = 112"
  FILTER_DIALECT = "mysql"
  TABLE_ALIAS = "TableAlias"
  RELATION_ALIAS = "RelationAlias"
  FACT_NAME = "order_fact"

  # Parses an XML string into a DOMWrapper for MondrianDef::Table constructor.
  def wrap_xml(xml_string)
    parser = Java::OrgEigenbaseXom::XOMUtil.createDefaultParser
    parser.parse(xml_string)
  end

  def fact_table_with_sql_filter
    <<~XML.chomp
      <Table name="sales_fact_1997" alias="TableAlias">
       <SQL dialect="mysql">
           `TableAlias`.`promotion_id` = 112
       </SQL>
      </Table>
    XML
  end

  def fact_table_with_empty_sql_filter
    <<~XML.chomp
      <Table name="sales_fact_1997" alias="TableAlias">
       <SQL dialect="mysql"/>
      </Table>
    XML
  end

  def fact_table_without_sql_filter
    <<~XML.chomp
      <Table name="sales_fact_1997" alias="TableAlias">
      </Table>
    XML
  end

  describe "makeRolapStarKey" do
    # Java: RolapUtilTest#testMakeRolapStarKeyUnmodifiable
    it "returns an unmodifiable list for fact table name" do
      rolap_star_key = RolapUtil.makeRolapStarKey(FACT_NAME)
      refute_nil rolap_star_key
      assert_raises(Java::JavaLang::UnsupportedOperationException) do
        rolap_star_key.add("OneMore")
      end
    end

    # Java: RolapUtilTest#testMakeRolapStarKey_ByFactTableName
    it "generates key from fact table name" do
      rolap_star_key = RolapUtil.makeRolapStarKey(FACT_NAME)
      refute_nil rolap_star_key
      assert_equal 1, rolap_star_key.size
      assert_equal FACT_NAME, rolap_star_key.get(0)
    end

    # Java: RolapUtilTest#testMakeRolapStarKey_FactTableWithSQLFilter
    it "generates key from fact table with SQL filter" do
      fact = MondrianDef::Table.new(wrap_xml(fact_table_with_sql_filter))
      rolap_star_key = RolapUtil.makeRolapStarKey(fact)
      refute_nil rolap_star_key
      assert_equal 3, rolap_star_key.size
      assert_equal TABLE_ALIAS, rolap_star_key.get(0)
      assert_equal FILTER_DIALECT, rolap_star_key.get(1)
      assert_equal FILTER_QUERY, rolap_star_key.get(2)
    end

    # Java: RolapUtilTest#testMakeRolapStarKey_FactTableWithEmptyFilter
    it "generates key from fact table with empty SQL filter" do
      fact = MondrianDef::Table.new(wrap_xml(fact_table_with_empty_sql_filter))
      rolap_star_key = RolapUtil.makeRolapStarKey(fact)
      refute_nil rolap_star_key
      assert_equal 1, rolap_star_key.size
      assert_equal TABLE_ALIAS, rolap_star_key.get(0)
    end

    # Java: RolapUtilTest#testMakeRolapStarKey_FactTableWithoutSQLFilter
    it "generates key from fact table without SQL filter" do
      fact = MondrianDef::Table.new(wrap_xml(fact_table_without_sql_filter))
      rolap_star_key = RolapUtil.makeRolapStarKey(fact)
      refute_nil rolap_star_key
      assert_equal 1, rolap_star_key.size
      assert_equal TABLE_ALIAS, rolap_star_key.get(0)
    end

    # Java: RolapUtilTest#testMakeRolapStarKey_FactRelation
    it "generates key from a non-Table relation" do
      relation = StubRelation.new(RELATION_ALIAS)
      rolap_star_key = RolapUtil.makeRolapStarKey(relation)
      refute_nil rolap_star_key
      assert_equal 1, rolap_star_key.size
      assert_equal RELATION_ALIAS, rolap_star_key.get(0)
    end
  end
end
