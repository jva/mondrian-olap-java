# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2006-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

MemberCacheHelper = Java::MondrianRolap::MemberCacheHelper
DefaultMemberChildrenConstraint = Java::MondrianRolap::DefaultMemberChildrenConstraint
NameSegment = Java::MondrianOlap::Id::NameSegment
RolapLevel = Java::MondrianRolap::RolapLevel

# Access Unsafe for allocating Java objects without calling constructors
unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
unsafe_field.accessible = true
UNSAFE = unsafe_field.get(nil)

# Mock RolapMember implementation using Ruby class with Java interface inclusion.
# Defined at file level to avoid constant lookup issues.
# become_java! is required to generate proper Java bridge methods for
# covariant return types (e.g., RolapMember.getParentMember() returning
# RolapMember instead of Member).
MockRolapMember = Class.new do
  include Java::MondrianRolap::RolapMember

  attr_accessor :mock_name, :mock_parent, :mock_level

  def initialize(name, parent_member: nil, level: nil)
    @mock_name = name
    @mock_parent = parent_member
    @mock_level = level
  end

  def getName
    @mock_name
  end

  def compareTo(other)
    @mock_name <=> other.getName
  end

  def getParentMember
    @mock_parent
  end

  def getLevel
    @mock_level
  end

  def getKey
    @mock_name
  end

  def to_s
    @mock_name
  end

  def hashCode
    @mock_name.hashCode
  end

  def equals(other)
    other.respond_to?(:getName) && @mock_name == other.getName
  end

  def isNull; false; end
  def isAll; false; end
  def isParentChildLeaf; false; end
  def isParentChildPhysicalMember; false; end
  def isAllMember; false; end
  def getHierarchy; nil; end
end
MockRolapMember.become_java!

# Java: mondrian/rolap/MemberCacheHelperTest.java
describe "MemberCacheHelper" do
  private

  # Sets a field on a Java object, searching up the class hierarchy.
  def set_java_field(object, field_name, value, declaring_class = nil)
    cls = declaring_class ? declaring_class.java_class : object.getClass
    field = nil
    while cls
      begin
        field = cls.getDeclaredField(field_name)
        break
      rescue java.lang.NoSuchFieldException
        cls = cls.getSuperclass
      end
    end
    raise "Field #{field_name} not found" unless field
    field.accessible = true
    field.set(object, value)
  end

  # Creates a mock RolapLevel via Unsafe with parentExp set to non-null
  # so that isParentChild() returns true. This prevents MemberKey.getLevel()
  # from calling getChildLevel() which requires a fully initialized hierarchy.
  def create_mock_level
    level = UNSAFE.allocateInstance(RolapLevel.java_class)
    set_java_field(level, "parentExp", Java::MondrianOlap::MondrianDef::Column.new)
    level
  end

  # Creates a mock RolapMember with the given name and optional parent.
  def create_mock_member(name, parent_member: nil)
    MockRolapMember.new(name, parent_member: parent_member, level: @mock_level)
  end

  # Creates a ChildByNameConstraint from an array of name strings via reflection
  # (the class is package-private).
  def create_child_by_name_constraint(names)
    segments = names.map { |name| NameSegment.new(name) }
    class_loader = MemberCacheHelper.java_class.getClassLoader
    constraint_class = java.lang.Class.forName(
      "mondrian.rolap.ChildByNameConstraint", true, class_loader
    )
    constructor = constraint_class.getDeclaredConstructor(java.util.List.java_class)
    constructor.setAccessible(true)
    constructor.newInstance(segments)
  end

  # Creates a MemberKey via reflection (package-private constructor).
  def create_member_key(parent_member, value)
    member_key_class = java.lang.Class.forName(
      "mondrian.rolap.MemberKey", true,
      Java::MondrianRolap::MemberCacheHelper.java_class.getClassLoader
    )
    constructor = member_key_class.getDeclaredConstructor(
      Java::MondrianRolap::RolapMember.java_class,
      java.lang.Object.java_class
    )
    constructor.setAccessible(true)
    constructor.newInstance(parent_member, value)
  end

  # Fills a list with mock RolapMember objects and returns the list of names.
  def fill_children(children, count)
    names = []
    count.times do |i|
      name = "Member-#{i}"
      names << name
      children << create_mock_member(name)
    end
    names
  end

  public

  before do
    @mock_level = create_mock_level
    @parent_member = create_mock_member("Parent")
    @default_constraint = DefaultMemberChildrenConstraint.instance
    @cache_helper = MemberCacheHelper.new(nil)
  end

  # Java: MemberCacheHelperTest#testRoundtripChildrenUsingChildByNameConstraint
  it "round-trips children using ChildByNameConstraint" do
    children = java.util.ArrayList.new
    child_names = fill_children(children, 3)
    constraint = create_child_by_name_constraint(child_names)

    @cache_helper.putChildren(@parent_member, constraint, children)

    retrieved_children = @cache_helper.getChildrenFromCache(@parent_member, constraint)

    retrieved = retrieved_children.to_a
    assert_equal children.size, retrieved.size
    children.each_with_index do |child, i|
      assert_same child, retrieved[i]
    end
  end

  # Java: MemberCacheHelperTest#testCachedByDefaultConstraint
  it "retrieves children cached under default constraint via ChildByNameConstraint" do
    children = java.util.ArrayList.new
    child_names = fill_children(children, 5)
    constraint = create_child_by_name_constraint(child_names)

    # Cached under default constraint, but subsequent
    # retrieval with childByName should work since all children present.
    @cache_helper.putChildren(@parent_member, @default_constraint, children)

    retrieved_children = @cache_helper.getChildrenFromCache(@parent_member, constraint)

    retrieved = retrieved_children.to_a
    assert_equal children.size, retrieved.size
    children.each_with_index do |child, i|
      assert_same child, retrieved[i]
    end
  end

  # Java: MemberCacheHelperTest#testOnlyRequestedChildrenRetrieved
  it "retrieves only requested children from cache keyed with DefaultMemberChildrenConstraint" do
    children = java.util.ArrayList.new
    child_names = fill_children(children, 5)

    from_index = 2
    to_index = 5
    # ChildByName constraint defined with member names in sublist
    constraint = create_child_by_name_constraint(child_names[from_index...to_index])

    # Cached under default constraint, but subsequent
    # retrieval with childByName should work since all children present.
    @cache_helper.putChildren(@parent_member, @default_constraint, children)

    retrieved_children = @cache_helper.getChildrenFromCache(@parent_member, constraint)

    expected = children.to_a[from_index...to_index]
    retrieved = retrieved_children.to_a
    assert_equal expected.size, retrieved.size, "Expected children were not retrieved from cache."
    expected.each_with_index do |child, i|
      assert_same child, retrieved[i], "Expected children were not retrieved from cache."
    end
  end

  # Java: MemberCacheHelperTest#testMissingChildrenNotRetrievedDefaultConst
  it "returns nil when requested children are missing (cached under default constraint)" do
    children = java.util.ArrayList.new
    fill_children(children, 5)
    constraint = create_child_by_name_constraint(%w[Other\ Name Other\ Name2])

    @cache_helper.putChildren(@parent_member, @default_constraint, children)

    retrieved_children = @cache_helper.getChildrenFromCache(@parent_member, constraint)

    assert_nil retrieved_children, "Not expecting to retrieve anything from cache"
  end

  # Java: MemberCacheHelperTest#testMissingChildrenNotRetrievedChildByName
  it "returns nil when requested children are missing (cached under ChildByNameConstraint)" do
    children = java.util.ArrayList.new
    child_names = fill_children(children, 5)
    put_constraint = create_child_by_name_constraint(child_names)
    get_constraint = create_child_by_name_constraint(%w[Other\ Name Other\ Name2])

    @cache_helper.putChildren(@parent_member, put_constraint, children)

    retrieved_children = @cache_helper.getChildrenFromCache(@parent_member, get_constraint)

    assert_nil retrieved_children, "Not expecting to retrieve anything from cache"
  end

  # Java: MemberCacheHelperTest#testRemoveChildMemberPresentInNamedChildrenMap
  it "removes a child member from the named children cache" do
    children = java.util.ArrayList.new
    child_names = fill_children(children, 3)
    constraint = create_child_by_name_constraint(child_names[1..2])
    child_keys = []

    children.each do |member|
      member.mock_parent = @parent_member
      member_key = create_member_key(member, member.getName)
      child_keys << member_key
      @cache_helper.putMember(member_key, member)
    end
    parent_key = create_member_key(@parent_member, "ParentKey")
    @cache_helper.putMember(parent_key, @parent_member)
    @cache_helper.putChildren(@parent_member, constraint, children)

    @cache_helper.removeMember(child_keys[0])

    members = @cache_helper.getChildrenFromCache(@parent_member, constraint)

    expected = children.to_a[1..2]
    retrieved = members.to_a
    assert_equal expected.size, retrieved.size, "Retrieved children should not include the removed member"
    expected.each_with_index do |child, i|
      assert_same child, retrieved[i], "Retrieved children should not include the removed member"
    end
  end
end
