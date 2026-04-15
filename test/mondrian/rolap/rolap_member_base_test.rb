# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (c) 2016-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapMemberBaseTest.java
describe "RolapMemberBase" do
  PROPERTY_NAME_1 = "property1"
  PROPERTY_NAME_2 = "property2"
  PROPERTY_NAME_3 = "property3"
  PROPERTY_VALUE_TO_FORMAT = "propertyValueToFormat"
  FORMATTED_PROPERTY_VALUE = "formattedPropertyValue"
  MEMBER_NAME = "memberName"
  FORMATTED_CAPTION = "formattedCaption"

  # Access Unsafe for allocating Java objects without calling constructors
  unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
  unsafe_field.accessible = true
  UNSAFE = unsafe_field.get(nil)

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

  # Creates a RolapDimension via Unsafe (bypasses constructor).
  # Sets uniqueName to avoid NPE in isMeasures().
  def create_mock_dimension
    dimension = UNSAFE.allocateInstance(Java::MondrianRolap::RolapDimension.java_class)
    set_java_field(dimension, "uniqueName", "TestDimension")
    dimension
  end

  # Creates a RolapHierarchy via Unsafe (bypasses constructor).
  # Wires the dimension field so getDimension() works.
  def create_mock_hierarchy(dimension)
    hierarchy = UNSAFE.allocateInstance(Java::MondrianRolap::RolapHierarchy.java_class)
    set_java_field(hierarchy, "dimension", dimension, Java::MondrianOlap::HierarchyBase)
    hierarchy
  end

  # Creates a RolapLevel via Unsafe (bypasses constructor).
  # Wires the hierarchy field on LevelBase and sets properties.
  def create_mock_level(hierarchy, properties: nil, member_formatter: nil)
    level = UNSAFE.allocateInstance(Java::MondrianRolap::RolapLevel.java_class)
    set_java_field(level, "hierarchy", hierarchy, Java::MondrianOlap::LevelBase)
    set_java_field(level, "properties", (properties || []).to_java(Java::MondrianRolap::RolapProperty))
    set_java_field(level, "memberFormatter", member_formatter) if member_formatter
    level
  end

  # Creates a RolapProperty via Unsafe (bypasses constructor).
  # Sets name and formatter fields.
  def create_mock_property(name, formatter: nil)
    property = UNSAFE.allocateInstance(Java::MondrianRolap::RolapProperty.java_class)
    set_java_field(property, "name", name, Java::MondrianOlap::Property)
    set_java_field(property, "formatter", formatter)
    property
  end

  # Creates a RolapMemberBase with the given level and key via reflection
  # (the 5-arg constructor is protected).
  def create_member(level, key)
    parent_member = create_null_rolap_member
    constructor = Java::MondrianRolap::RolapMemberBase.java_class.getDeclaredConstructor(
      Java::MondrianRolap::RolapMember.java_class,
      Java::MondrianRolap::RolapLevel.java_class,
      java.lang.Object.java_class,
      java.lang.String.java_class,
      Java::MondrianOlap::Member::MemberType.java_class
    )
    constructor.accessible = true
    constructor.newInstance(
      parent_member,
      level,
      key,
      nil,
      Java::MondrianOlap::Member::MemberType::REGULAR
    )
  end

  # Creates a minimal RolapMember proxy that returns nil for most calls.
  def create_null_rolap_member
    handler = ->(_, method, _args) {
      case method.getName
      when "getLevel" then nil
      when "getHierarchy" then nil
      when "getParentMember" then nil
      when "getParentUniqueName" then nil
      when "getKey" then nil
      when "isAll" then false
      when "isNull" then false
      when "isMeasure" then false
      when "isCalculated" then false
      when "isEvaluated" then false
      end
    }

    interfaces = collect_interfaces(Java::MondrianRolap::RolapMember.java_class)
    java.lang.reflect.Proxy.newProxyInstance(
      Java::MondrianRolap::RolapMember.java_class.getClassLoader,
      interfaces,
      handler
    )
  end

  # Collects all interfaces from a given interface, including parent interfaces.
  def collect_interfaces(interface_class)
    interfaces = java.util.LinkedHashSet.new
    add_interface_tree(interface_class, interfaces)
    interfaces.toArray(java.lang.Class[interfaces.size].new)
  end

  def add_interface_tree(iface, set)
    return unless set.add(iface)
    iface.getInterfaces.each { |parent| add_interface_tree(parent, set) }
  end

  public

  before do
    @dimension = create_mock_dimension
    @hierarchy = create_mock_hierarchy(@dimension)
    @level = create_mock_level(@hierarchy)
    @member_key = java.lang.Integer.new(java.lang.Integer::MAX_VALUE)
    @member = create_member(@level, @member_key)
  end

  # Java: RolapMemberBaseTest#testShouldUsePropertyFormatterWhenPropertyValuesAreRequested
  it "uses property formatter when property values are requested" do
    property_formatter = Class.new do
      include Java::MondrianSpi::PropertyFormatter

      def formatProperty(_member, _property_name, _property_value)
        "formattedPropertyValue"
      end
    end.new

    property1 = create_mock_property(PROPERTY_NAME_1, formatter: property_formatter)
    property2 = create_mock_property(PROPERTY_NAME_2)
    properties = [property1, property2].to_java(Java::MondrianRolap::RolapProperty)
    set_java_field(@level, "properties", properties)

    @member.setProperty(PROPERTY_NAME_1, PROPERTY_VALUE_TO_FORMAT)
    @member.setProperty(PROPERTY_NAME_2, PROPERTY_VALUE_TO_FORMAT)

    formatted1 = @member.getPropertyFormattedValue(PROPERTY_NAME_1)
    formatted2 = @member.getPropertyFormattedValue(PROPERTY_NAME_2)
    formatted3 = @member.getPropertyFormattedValue(PROPERTY_NAME_3)

    # property1 has a formatter, so it should return the formatted value
    assert_equal FORMATTED_PROPERTY_VALUE, formatted1
    # property2 has no formatter, so it should return the raw value as a string
    assert_equal PROPERTY_VALUE_TO_FORMAT, formatted2
    # property3 does not exist, so it should return nil
    assert_nil formatted3
  end

  # Java: RolapMemberBaseTest#testShouldUseMemberFormatterForCaption
  it "uses member formatter for caption" do
    member_formatter = Class.new do
      include Java::MondrianSpi::MemberFormatter

      def formatMember(_member)
        "formattedCaption"
      end
    end.new

    set_java_field(@level, "memberFormatter", member_formatter)

    caption = @member.getCaption

    assert_equal FORMATTED_CAPTION, caption
  end

  # Java: RolapMemberBaseTest#testShouldNotFailIfMemberFormatterIsNotPresent
  it "does not fail if member formatter is not present" do
    # No member formatter set on level (null by default from Unsafe allocation).
    # Should fall back to getName(), which returns String.valueOf(key).
    caption = @member.getCaption

    assert_equal java.lang.Integer::MAX_VALUE.to_s, caption
  end

  # Java: RolapMemberBaseTest#testShouldReturnMemberKeyIfNoCaptionValueAndNoNamePresent
  it "returns member key if no caption value and no name present" do
    caption_value = @member.getCaptionValue

    refute_nil caption_value
    assert_equal java.lang.Integer::MAX_VALUE, caption_value
  end

  # Java: RolapMemberBaseTest#testShouldReturnMemberNameIfCaptionValueIsNotPresent
  it "returns member name if caption value is not present" do
    @member.setProperty(Java::MondrianOlap::Property::NAME.name, MEMBER_NAME)

    caption_value = @member.getCaptionValue

    refute_nil caption_value
    assert_equal MEMBER_NAME, caption_value
  end

  # Java: RolapMemberBaseTest#testShouldReturnCaptionValueIfPresent
  it "returns caption value if present" do
    @member.setCaptionValue(java.lang.Integer.new(java.lang.Integer::MIN_VALUE))

    caption_value = @member.getCaptionValue

    refute_nil caption_value
    assert_equal java.lang.Integer::MIN_VALUE, caption_value
  end
end
