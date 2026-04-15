# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

TupleCollections = Java::MondrianCalc::TupleCollections
RolapAxis = Java::MondrianRolap::RolapAxis

# Minimal Member implementation for unit testing, mirroring Java's TestMember.
# Defined at file level to avoid JRuby constant lookup issues.
class StubMember
  include Java::MondrianOlap::Member

  def initialize(identifier)
    @identifier = identifier
  end

  def toString
    @identifier
  end

  def to_s
    @identifier
  end

  def compareTo(other)
    @identifier <=> other.toString
  end

  def getDimension
    nil
  end

  def getHierarchy
    nil
  end

  def getLevel
    nil
  end

  def getParentMember
    nil
  end

  def getParentUniqueName
    nil
  end

  def getMemberType
    nil
  end

  def isParentChildLeaf
    false
  end

  def isParentChildPhysicalMember
    false
  end

  def setName(_name)
    raise java.lang.UnsupportedOperationException.new
  end

  def isAll
    false
  end

  def isMeasure
    false
  end

  def isNull
    true
  end

  def isChildOrEqualTo(_member)
    false
  end

  def isCalculated
    false
  end

  def isEvaluated
    false
  end

  def getSolveOrder
    0
  end

  def getExpression
    nil
  end

  def getAncestorMembers
    java.util.Collections.emptyList
  end

  def isCalculatedInQuery
    false
  end

  def getPropertyValue(*_args)
    nil
  end

  def getPropertyFormattedValue(_name)
    nil
  end

  def setProperty(_name, _value)
    raise java.lang.UnsupportedOperationException.new
  end

  def getProperties
    [].to_java(Java::MondrianOlap::Property)
  end

  def getOrdinal
    0
  end

  def getOrderKey
    nil
  end

  def isHidden
    false
  end

  def getDepth
    0
  end

  def getDataMember
    nil
  end

  def isOnSameHierarchyChain(_other)
    false
  end

  def getUniqueName
    @identifier
  end

  def getName
    @identifier
  end

  def getDescription
    nil
  end

  def lookupChild(*_args)
    nil
  end

  def getQualifiedName
    @identifier
  end

  def getCaption
    @identifier
  end

  def getLocalized(*_args)
    nil
  end

  def isVisible
    true
  end

  def getAnnotationMap
    java.util.Collections.emptyMap
  end
end

# Java: mondrian/rolap/RolapAxisTest.java
describe "RolapAxis" do
  def position_to_string(position)
    buf = "{"
    first = true
    position.each do |m|
      unless first
        buf += ","
      end
      buf += m.toString
      first = false
    end
    buf += "}"
    buf
  end

  # Java: RolapAxisTest#testMemberArrayList
  it "iterates and indexes positions from a member array tuple list" do
    list = TupleCollections.createList(3)
    list.add(
      java.util.Arrays.asList(
        StubMember.new("a"),
        StubMember.new("b"),
        StubMember.new("c")))
    list.add(
      java.util.Arrays.asList(
        StubMember.new("d"),
        StubMember.new("e"),
        StubMember.new("f")))
    list.add(
      java.util.Arrays.asList(
        StubMember.new("g"),
        StubMember.new("h"),
        StubMember.new("i")))

    axis = RolapAxis.new(list)

    # Iterate positions via each
    positions = axis.getPositions
    parts = []
    positions.each do |position|
      parts << position_to_string(position)
    end
    s = parts.join(",")
    assert_equal "{a,b,c},{d,e,f},{g,h,i}", s

    # Check size
    positions = axis.getPositions
    assert_equal 3, positions.size

    # Access positions by index
    parts = []
    positions.size.times do |i|
      position = positions.get(i)
      parts << position_to_string(position)
    end
    s = parts.join(",")
    assert_equal "{a,b,c},{d,e,f},{g,h,i}", s
  end
end
