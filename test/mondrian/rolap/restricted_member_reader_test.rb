# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2018 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# InvocationHandler for a Role proxy that returns a configurable HierarchyAccess.
class RmrRoleHandler
  include java.lang.reflect.InvocationHandler

  def initialize(hierarchy_access)
    @hierarchy_access = hierarchy_access
  end

  def invoke(_proxy, method, _args)
    return @hierarchy_access if method.getName == "getAccessDetails"
    nil
  end
end

# InvocationHandler for a HierarchyAccess proxy with configurable per-member access.
class RmrHierarchyAccessHandler
  include java.lang.reflect.InvocationHandler

  def initialize
    @access_map = {}
    @default_access = nil
  end

  # Set access for a specific member (by Java identity hash code).
  def set_access(member, access)
    @access_map[java.lang.System.identityHashCode(member)] = access
  end

  # Set a default access for any member not in the map.
  def set_default_access(access)
    @default_access = access
  end

  # Clear all per-member access overrides.
  def clear_access
    @access_map.clear
  end

  def invoke(_proxy, method, args)
    case method.getName
    when "getAccess"
      member = args.to_a[0]
      identity = java.lang.System.identityHashCode(member)
      return @access_map[identity] if @access_map.key?(identity)
      return @default_access
    when "getTopLevelDepth"
      java.lang.Integer.new(0)
    when "getBottomLevelDepth"
      java.lang.Integer.new(100)
    when "getRollupPolicy"
      Java::MondrianOlap::Role::RollupPolicy::FULL
    when "hasInaccessibleDescendants"
      false
    end
  end
end

# InvocationHandler for a MemberReader proxy.
class RmrMemberReaderHandler
  include java.lang.reflect.InvocationHandler

  def initialize(hierarchy, root_members)
    @hierarchy = hierarchy
    @root_members = root_members
  end

  def invoke(_proxy, method, _args)
    case method.getName
    when "getHierarchy"
      @hierarchy
    when "getRootMembers"
      @root_members
    else
      nil
    end
  end
end

# InvocationHandler for a RolapMember proxy with configurable behavior.
class RmrMockMemberHandler
  include java.lang.reflect.InvocationHandler

  attr_accessor :is_measure, :is_hidden, :is_null

  def initialize(identity)
    @identity = identity
    @is_measure = false
    @is_hidden = false
    @is_null = false
  end

  def invoke(_proxy, method, _args)
    case method.getName
    when "isMeasure"  then @is_measure
    when "isHidden"   then @is_hidden
    when "isNull"     then @is_null
    when "isAll", "isParentChildLeaf", "isParentChildPhysicalMember", "isAllMember"
      false
    when "hashCode"
      java.lang.Integer.new(@identity)
    when "equals"
      false
    when "toString"
      "MockMember(#{@identity})"
    else
      nil
    end
  end
end

# Java: mondrian/rolap/RestrictedMemberReaderTest.java
describe "RestrictedMemberReader" do
  before(:all) do
    create_olap_connection
    @class_loader = @olap.raw_mondrian_connection.getClass.getClassLoader
    @unsafe = obtain_unsafe
    @null_default_hierarchy_class = define_null_default_hierarchy_class
  end

  after(:all) do
    @olap.close if @olap
  end

  def obtain_unsafe
    unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
    unsafe_field.accessible = true
    unsafe_field.get(nil)
  end

  # Generate a bytecode subclass of RolapHierarchy that overrides getDefaultMember() to return null.
  # This replicates the Mockito mock behavior in the Java test where hierarchy.getDefaultMember()
  # is stubbed to return null, bypassing RolapHierarchy's lazy initialization that would otherwise
  # throw when fields are not fully set up.
  def define_null_default_hierarchy_class
    class_name = "mondrian.rolap.NullDefaultMemberHierarchy"

    # Return the existing class if already defined in this classloader.
    begin
      return java.lang.Class.forName(class_name, true, @class_loader)
    rescue java.lang.ClassNotFoundException
      # Not yet defined; generate and define it below.
    end

    asm_cw = org.jruby.org.objectweb.asm.ClassWriter
    asm_op = org.jruby.org.objectweb.asm.Opcodes

    cw = asm_cw.new(asm_cw::COMPUTE_FRAMES | asm_cw::COMPUTE_MAXS)
    cw.visit(asm_op::V1_8, asm_op::ACC_PUBLIC,
             "mondrian/rolap/NullDefaultMemberHierarchy", nil,
             "mondrian/rolap/RolapHierarchy", nil)

    mv = cw.visitMethod(asm_op::ACC_PUBLIC, "getDefaultMember",
                        "()Lmondrian/olap/Member;", nil, nil)
    mv.visitCode
    mv.visitInsn(asm_op::ACONST_NULL)
    mv.visitInsn(asm_op::ARETURN)
    mv.visitMaxs(1, 1)
    mv.visitEnd
    cw.visitEnd

    bytecode_array = cw.toByteArray

    # Use Unsafe to obtain IMPL_LOOKUP (bypasses Java module access restrictions),
    # then define the class in the Mondrian classloader via MethodHandle.
    lookup_class = java.lang.Class.forName("java.lang.invoke.MethodHandles$Lookup")
    impl_lookup_field = lookup_class.getDeclaredField("IMPL_LOOKUP")
    impl_lookup = @unsafe.getObject(lookup_class, @unsafe.staticFieldOffset(impl_lookup_field))

    param_types = [java.lang.String.java_class, Java::byte[].java_class,
                   Java::int.java_class, Java::int.java_class].to_java(java.lang.Class)
    method_type = java.lang.invoke.MethodType.methodType(java.lang.Class.java_class, param_types)
    define_mh = impl_lookup.findVirtual(java.lang.ClassLoader.java_class, "defineClass", method_type)

    define_mh.invokeWithArguments(
      @class_loader,
      class_name,
      bytecode_array,
      java.lang.Integer.new(0),
      java.lang.Integer.new(bytecode_array.length)
    )
  end

  def find_java_class(name)
    java.lang.Class.forName(name, true, @class_loader)
  end

  # Find a declared field traversing the Java class hierarchy.
  def find_declared_field(java_class, field_name)
    cls = java_class
    while cls
      begin
        return cls.getDeclaredField(field_name)
      rescue java.lang.NoSuchFieldException
        cls = cls.getSuperclass
      end
    end
    raise "Field '#{field_name}' not found on #{java_class.getName}"
  end

  # Set a field value on a Java object via reflection.
  def set_field(object, field_name, value)
    field = find_declared_field(object.getClass, field_name)
    field.setAccessible(true)
    field.set(object, value)
  end

  # Get a field value from a Java object via reflection.
  def get_field(object, field_name)
    field = find_declared_field(object.getClass, field_name)
    field.setAccessible(true)
    field.get(object)
  end

  # Create a bare RolapHierarchy via Unsafe (no constructor invocation).
  # Sets only the fields needed by RestrictedMemberReader's constructor and methods.
  def create_mock_hierarchy(default_member: nil, ragged: false)
    hierarchy_class = find_java_class("mondrian.rolap.RolapHierarchy")
    hierarchy = @unsafe.allocateInstance(hierarchy_class)

    # Set defaultMember field (in RolapHierarchy).
    default_member_field = find_declared_field(hierarchy_class, "defaultMember")
    default_member_field.setAccessible(true)
    default_member_field.set(hierarchy, default_member)

    # Set levels field (in HierarchyBase) for isRagged().
    levels_field = find_declared_field(hierarchy_class, "levels")
    levels_field.setAccessible(true)
    if ragged
      # Create a mock RolapLevel with HideMemberCondition.IfBlankName via Unsafe.
      level = create_ragged_level
      levels_field.set(hierarchy, [level].to_java(find_java_class("mondrian.olap.Level")))
    else
      levels_field.set(hierarchy, [].to_java(find_java_class("mondrian.olap.Level")))
    end

    # For the allAccess path (getAccessDetails returns null):
    # RoleImpl.createAllAccess calls hierarchy.getDimension().getSchema().
    # Set dimension field (in HierarchyBase) to a real dimension.
    if ragged
      real_schema = @olap.raw_mondrian_connection.getSchema
      real_cube = real_schema.getCubes.find { |c| c.getName == "Sales" }
      real_dimension = real_cube.getDimensions[0]
      dimension_field = find_declared_field(hierarchy_class, "dimension")
      dimension_field.setAccessible(true)
      dimension_field.set(hierarchy, real_dimension)
    end

    hierarchy
  end

  # Create a hierarchy instance whose getDefaultMember() returns null.
  # Uses the ASM-generated NullDefaultMemberHierarchy subclass which overrides
  # getDefaultMember() at the bytecode level, matching the Java test's Mockito mock.
  def create_null_default_hierarchy
    hierarchy = @unsafe.allocateInstance(@null_default_hierarchy_class)

    # Set levels field (in HierarchyBase) for isRagged() - empty means not ragged.
    hierarchy_class = find_java_class("mondrian.rolap.RolapHierarchy")
    levels_field = find_declared_field(hierarchy_class, "levels")
    levels_field.setAccessible(true)
    levels_field.set(hierarchy, [].to_java(find_java_class("mondrian.olap.Level")))

    hierarchy
  end

  # Create a RolapLevel with HideMemberCondition != Never via Unsafe.
  def create_ragged_level
    level_class = find_java_class("mondrian.rolap.RolapLevel")
    level = @unsafe.allocateInstance(level_class)
    condition_field = find_declared_field(level_class, "hideMemberCondition")
    condition_field.setAccessible(true)
    condition_field.set(level, Java::MondrianRolap::RolapLevel::HideMemberCondition::IfBlankName)
    level
  end

  # Construct RestrictedMemberReader via reflection (package-private constructor).
  def create_restricted_member_reader(member_reader, role)
    rmr_class = find_java_class("mondrian.rolap.RestrictedMemberReader")
    member_reader_iface = find_java_class("mondrian.rolap.MemberReader")
    role_iface = find_java_class("mondrian.olap.Role")
    constructor = rmr_class.getDeclaredConstructor(member_reader_iface, role_iface)
    constructor.setAccessible(true)
    constructor.newInstance(member_reader, role)
  end

  # Invoke the package-private processMemberChildren method via reflection.
  def invoke_process_member_children(rmr, full_children, children, constraint)
    rmr_class = find_java_class("mondrian.rolap.RestrictedMemberReader")
    method = rmr_class.getDeclaredMethod(
      "processMemberChildren",
      java.util.List.java_class,
      java.util.List.java_class,
      find_java_class("mondrian.rolap.sql.MemberChildrenConstraint")
    )
    method.setAccessible(true)
    method.invoke(rmr, full_children, children, constraint)
  end

  # Create a proxy for the MemberReader interface.
  def create_member_reader_proxy(hierarchy, root_members = java.util.ArrayList.new)
    handler = RmrMemberReaderHandler.new(hierarchy, root_members)
    member_reader_iface = find_java_class("mondrian.rolap.MemberReader")
    member_source_iface = find_java_class("mondrian.rolap.MemberSource")
    java.lang.reflect.Proxy.newProxyInstance(
      @class_loader,
      [member_reader_iface, member_source_iface].to_java(java.lang.Class),
      handler
    )
  end

  # Create a proxy for the Role interface.
  def create_role_proxy(hierarchy_access)
    handler = RmrRoleHandler.new(hierarchy_access)
    role_iface = find_java_class("mondrian.olap.Role")
    java.lang.reflect.Proxy.newProxyInstance(
      @class_loader,
      [role_iface].to_java(java.lang.Class),
      handler
    )
  end

  # Create a proxy for the HierarchyAccess interface with controllable access.
  def create_hierarchy_access_proxy
    handler = RmrHierarchyAccessHandler.new
    ha_iface = find_java_class("mondrian.olap.Role$HierarchyAccess")
    proxy = java.lang.reflect.Proxy.newProxyInstance(
      @class_loader,
      [ha_iface].to_java(java.lang.Class),
      handler
    )
    [proxy, handler]
  end

  # Create a mock RolapMember proxy.
  def create_mock_member(identity = rand(100_000))
    handler = RmrMockMemberHandler.new(identity)
    rolap_member_iface = find_java_class("mondrian.rolap.RolapMember")
    proxy = java.lang.reflect.Proxy.newProxyInstance(
      @class_loader,
      [rolap_member_iface].to_java(java.lang.Class),
      handler
    )
    [proxy, handler]
  end

  # Create a Java List of RolapMember proxies.
  def member_list(*members)
    rolap_member_iface = find_java_class("mondrian.rolap.RolapMember")
    java.util.Arrays.asList(members.to_java(rolap_member_iface))
  end

  def multi_cardinality_class
    find_java_class("mondrian.rolap.RestrictedMemberReader$MultiCardinalityDefaultMember")
  end

  describe "getHierarchy" do
    # Java: RestrictedMemberReaderTest#testGetHierarchy_allAccess
    it "returns hierarchy with all access" do
      hierarchy = create_mock_hierarchy(ragged: true)
      member_reader = create_member_reader_proxy(hierarchy)
      role = create_role_proxy(nil)

      rmr = create_restricted_member_reader(member_reader, role)

      assert_same hierarchy, rmr.getHierarchy
    end

    # Java: RestrictedMemberReaderTest#testGetHierarchy_roleAccess
    it "returns hierarchy with role access" do
      hierarchy = create_mock_hierarchy
      hierarchy_access, _handler = create_hierarchy_access_proxy
      member_reader = create_member_reader_proxy(hierarchy)
      role = create_role_proxy(hierarchy_access)

      rmr = create_restricted_member_reader(member_reader, role)

      assert_same hierarchy, rmr.getHierarchy
    end
  end

  describe "getDefaultMember" do
    # Java: RestrictedMemberReaderTest#testDefaultMember_allAccess
    it "returns hierarchy default member with all access" do
      mock_default, _handler = create_mock_member(1)
      hierarchy = create_mock_hierarchy(default_member: mock_default, ragged: true)
      member_reader = create_member_reader_proxy(hierarchy)
      role = create_role_proxy(nil)

      rmr = create_restricted_member_reader(member_reader, role)

      assert_same mock_default, rmr.getDefaultMember
    end

    # Java: RestrictedMemberReaderTest#testDefaultMember_roleAccess
    it "returns appropriate default member with role access" do
      hierarchy_access, ha_handler = create_hierarchy_access_proxy
      member0, _m0_handler = create_mock_member(100)
      hier_default_member = member0
      root_members = member_list(member0)

      hierarchy = create_mock_hierarchy(default_member: hier_default_member)
      member_reader = create_member_reader_proxy(hierarchy, root_members)
      role = create_role_proxy(hierarchy_access)
      rmr = create_restricted_member_reader(member_reader, role)

      # Access is null: default member is returned
      ha_handler.set_default_access(nil)
      assert_same hier_default_member, rmr.getDefaultMember, "on Access is null"

      # Access.ALL: default member is returned
      ha_handler.set_default_access(Java::MondrianOlap::Access::ALL)
      assert_same hier_default_member, rmr.getDefaultMember, "on Access.ALL"

      # Access.CUSTOM: default member is returned
      ha_handler.set_default_access(Java::MondrianOlap::Access::CUSTOM)
      assert_same hier_default_member, rmr.getDefaultMember, "on Access.CUSTOM"

      # Access.NONE: returns a MultiCardinalityDefaultMember
      ha_handler.set_default_access(Java::MondrianOlap::Access::NONE)
      default_member = rmr.getDefaultMember
      refute_same hier_default_member, default_member, "on Access.NONE"
      assert_equal true, multi_cardinality_class.isInstance(default_member)
    end

    # Java: RestrictedMemberReaderTest#testDefaultMember_noDefaultMember_roleAccess
    # The Java test mocks hierarchy.getDefaultMember() to return null.
    # We use an ASM-generated subclass of RolapHierarchy that overrides getDefaultMember()
    # to return null at the bytecode level, exercising the null-default-member code path
    # in RestrictedMemberReader.getDefaultMember().
    it "returns first root member when hierarchy has no default member" do
      hierarchy_access, ha_handler = create_hierarchy_access_proxy
      member0, _m0_handler = create_mock_member(200)
      root_members = member_list(member0)

      hierarchy = create_null_default_hierarchy
      member_reader = create_member_reader_proxy(hierarchy, root_members)
      role = create_role_proxy(hierarchy_access)
      rmr = create_restricted_member_reader(member_reader, role)

      # Access is null for root members: first root member is returned
      ha_handler.set_default_access(nil)
      assert_same member0, rmr.getDefaultMember, "on Access is null"

      # Access.ALL: first root member is returned
      ha_handler.set_default_access(Java::MondrianOlap::Access::ALL)
      assert_same member0, rmr.getDefaultMember, "on Access.ALL"

      # Access.CUSTOM: first root member is returned
      ha_handler.set_default_access(Java::MondrianOlap::Access::CUSTOM)
      assert_same member0, rmr.getDefaultMember, "on Access.CUSTOM"

      # Access.NONE for root members: returns a MultiCardinalityDefaultMember
      ha_handler.set_default_access(Java::MondrianOlap::Access::NONE)
      default_member = rmr.getDefaultMember
      refute_same member0, default_member, "on Access.NONE"
      assert_equal true, multi_cardinality_class.isInstance(default_member)
    end

    # Java: RestrictedMemberReaderTest#testDefaultMember_multiRoot
    it "returns correct default member with multiple root members" do
      hierarchy_access, ha_handler = create_hierarchy_access_proxy
      member0, _m0_handler = create_mock_member(300)
      member1, _m1_handler = create_mock_member(301)
      member2, _m2_handler = create_mock_member(302)
      root_members = member_list(member0, member1, member2)
      hier_default_member = member1

      hierarchy = create_mock_hierarchy(default_member: hier_default_member)
      member_reader = create_member_reader_proxy(hierarchy, root_members)
      role = create_role_proxy(hierarchy_access)
      rmr = create_restricted_member_reader(member_reader, role)

      # Access C-N-N: member0 has CUSTOM, member1 and member2 have NONE
      ha_handler.set_access(member0, Java::MondrianOlap::Access::CUSTOM)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::NONE)
      assert_same member0, rmr.getDefaultMember, "on Access C-N-N"

      # Access N-N-C: member0 and member1 have NONE, member2 has CUSTOM
      ha_handler.set_access(member0, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::CUSTOM)
      assert_same member2, rmr.getDefaultMember, "on Access N-N-C"

      # Access C-C-C: all have CUSTOM, default member (member1) has access
      ha_handler.set_access(member0, Java::MondrianOlap::Access::CUSTOM)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::CUSTOM)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::CUSTOM)
      assert_same hier_default_member, rmr.getDefaultMember, "on Access C-C-C"

      # Access C-N-C: multiple accessible roots with inaccessible default
      ha_handler.set_access(member0, Java::MondrianOlap::Access::CUSTOM)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::CUSTOM)
      assert_equal true, multi_cardinality_class.isInstance(rmr.getDefaultMember), "on Access C-N-C"

      # Access.NONE for all: MultiCardinalityDefaultMember
      ha_handler.set_access(member0, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::NONE)
      assert_equal true, multi_cardinality_class.isInstance(rmr.getDefaultMember), "on Access.NONE"
    end

    # Java: RestrictedMemberReaderTest#testDefaultMember_multiRootMeasure
    it "returns correct default member with multiple root measure members" do
      hierarchy_access, ha_handler = create_hierarchy_access_proxy
      member0, m0_handler = create_mock_member(400)
      member1, m1_handler = create_mock_member(401)
      member2, m2_handler = create_mock_member(402)

      # Mark all members as measures
      m0_handler.is_measure = true
      m1_handler.is_measure = true
      m2_handler.is_measure = true

      root_members = member_list(member0, member1, member2)
      hier_default_member = member1

      hierarchy = create_mock_hierarchy(default_member: hier_default_member)
      member_reader = create_member_reader_proxy(hierarchy, root_members)
      role = create_role_proxy(hierarchy_access)
      rmr = create_restricted_member_reader(member_reader, role)

      # Access C-N-N: member0 has CUSTOM, others NONE -> member0
      ha_handler.set_access(member0, Java::MondrianOlap::Access::CUSTOM)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::NONE)
      assert_same member0, rmr.getDefaultMember, "on Access C-N-N"

      # Access N-N-C: member0 and member1 NONE, member2 CUSTOM -> member2
      ha_handler.set_access(member0, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::CUSTOM)
      assert_same member2, rmr.getDefaultMember, "on Access N-N-C"

      # Access C-C-C: all CUSTOM, default member (member1) has access
      ha_handler.set_access(member0, Java::MondrianOlap::Access::CUSTOM)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::CUSTOM)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::CUSTOM)
      assert_same hier_default_member, rmr.getDefaultMember, "on Access C-C-C"

      # Access C-N-C: For measures, multiple accessible roots returns first accessible
      ha_handler.set_access(member0, Java::MondrianOlap::Access::CUSTOM)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::CUSTOM)
      assert_same member0, rmr.getDefaultMember, "on Access C-N-C"

      # Access.NONE for all: MultiCardinalityDefaultMember
      ha_handler.set_access(member0, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member1, Java::MondrianOlap::Access::NONE)
      ha_handler.set_access(member2, Java::MondrianOlap::Access::NONE)
      assert_equal true, multi_cardinality_class.isInstance(rmr.getDefaultMember), "on Access.NONE"
    end
  end

  describe "processMemberChildren" do
    # Java: RestrictedMemberReaderTest#testProcessMemberChildren
    it "returns map with access for all full children" do
      hierarchy = create_mock_hierarchy(ragged: true)
      member_reader = create_member_reader_proxy(hierarchy)
      role = create_role_proxy(nil)
      rmr = create_restricted_member_reader(member_reader, role)

      mock_member1, _h1 = create_mock_member(500)
      mock_member2, _h2 = create_mock_member(501)
      mock_child, _hc = create_mock_member(502)

      children = java.util.ArrayList.new
      children.add(mock_child)

      full_children = java.util.ArrayList.new
      full_children.add(mock_member1)
      full_children.add(mock_member2)

      result = invoke_process_member_children(rmr, full_children, children, nil)

      assert_equal 2, result.size
      assert_equal true, result.containsValue(Java::MondrianOlap::Access::ALL)
    end
  end
end
