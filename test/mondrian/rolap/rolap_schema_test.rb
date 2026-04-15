# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2015-2017 Hitachi Vantara
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../test_helper"

# Java: mondrian/rolap/RolapSchemaTest.java
describe "RolapSchema" do
  # Access Unsafe for allocating Java objects without calling constructors
  unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
  unsafe_field.accessible = true
  UNSAFE_RS = unsafe_field.get(nil)

  private

  def find_java_class(name)
    class_loader = Java::MondrianRolap::RolapSchema.java_class.getClassLoader
    java.lang.Class.forName(name, true, class_loader)
  end

  def set_java_field(object, field_name, value, search_class = nil)
    cls = search_class || object.getClass
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

  def get_java_field(object, field_name, search_class = nil)
    cls = search_class || object.getClass
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
    field.get(object)
  end

  def find_method(object, method_name, param_types = [])
    cls = object.java_class rescue object.getClass
    while cls
      begin
        method = cls.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
        method.accessible = true
        return method
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end
    raise "Method #{method_name} not found"
  end

  # Creates a RolapSchema using the deprecated test constructor via reflection.
  # This mirrors the Java test's createSchema() method.
  def create_schema
    # Create SchemaKey from package-private classes via Unsafe
    string_key_class = find_java_class("mondrian.util.StringKey")

    schema_content_key = UNSAFE_RS.allocateInstance(find_java_class("mondrian.rolap.SchemaContentKey"))
    set_java_field(schema_content_key, "value", "test-content", string_key_class)

    connection_key = UNSAFE_RS.allocateInstance(find_java_class("mondrian.rolap.ConnectionKey"))
    set_java_field(connection_key, "value", "test-connection", string_key_class)

    schema_key_class = find_java_class("mondrian.rolap.SchemaKey")
    schema_key = UNSAFE_RS.allocateInstance(schema_key_class)
    set_java_field(schema_key, "left", schema_content_key, Java::MondrianUtil::Pair.java_class)
    set_java_field(schema_key, "right", connection_key, Java::MondrianUtil::Pair.java_class)

    md5 = Java::MondrianUtil::ByteString.new("test schema".to_java_bytes)

    # Use Unsafe to allocate the schema without calling the constructor
    schema = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapSchema.java_class)

    # Set the fields that the deprecated test constructor would set
    set_java_field(schema, "id", Java::MondrianOlap::Util.generateUuidString)
    set_java_field(schema, "key", schema_key)
    set_java_field(schema, "md5Bytes", md5)
    set_java_field(schema, "defaultRole", Java::MondrianOlap::Util.createRootRole(schema))

    # Initialize mapNameToRole (used by createUnionRole)
    set_java_field(schema, "mapNameToRole", java.util.HashMap.new)

    # Initialize mapNameToCube (used by lookupCube)
    set_java_field(schema, "mapNameToCube", java.util.HashMap.new)

    # Initialize rolapStarRegistry
    registry_class = find_java_class("mondrian.rolap.RolapSchema$RolapStarRegistry")
    registry = UNSAFE_RS.allocateInstance(registry_class)
    # Set the outer class reference (this$0)
    set_java_field(registry, "this$0", schema)
    # Initialize the stars map
    set_java_field(registry, "stars", java.util.HashMap.new)
    set_java_field(schema, "rolapStarRegistry", registry)

    schema
  end

  # Creates a minimal RolapCube via Unsafe with a no-op SchemaReader,
  # and registers it in the schema's mapNameToCube.
  def create_and_register_cube(schema, name)
    cube = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapCube.java_class)
    set_java_field(cube, "schema", schema)
    set_java_field(cube, "name", name, Java::MondrianOlap::CubeBase.java_class)
    set_java_field(cube, "uniqueName", "[#{name}]", Java::MondrianOlap::CubeBase.java_class)

    # Create a no-op SchemaReader proxy for cube.getSchemaReader(null)
    noop_reader = java.lang.reflect.Proxy.newProxyInstance(
      Java::MondrianOlap::SchemaReader.java_class.getClassLoader,
      [Java::MondrianOlap::SchemaReader.java_class].to_java(java.lang.Class),
      proc { |proxy, method, _args| proxy if method.getName == "withLocus" }
    )
    set_java_field(cube, "schemaReader", noop_reader)

    map_name_to_cube = get_java_field(schema, "mapNameToCube")
    map_name_to_cube.put(Java::MondrianOlap::Util.normalizeName(name), cube)
    cube
  end

  # Invokes a package-private method on the schema via reflection.
  # Unwraps InvocationTargetException to re-raise the original exception.
  def invoke_schema_method(schema, method_name, param_classes, *args)
    method = find_method(schema, method_name, param_classes)
    method.invoke(schema, *args)
  rescue java.lang.reflect.InvocationTargetException => e
    raise e.cause
  end

  # Parses an XML string into a DOMWrapper for MondrianDef.Table constructor.
  def wrap_xml(xml_string)
    parser = Java::OrgEigenbaseXom::XOMUtil.createDefaultParser
    parser.parse(xml_string)
  end

  public

  describe "createUnionRole" do
    # Java: RolapSchemaTest#testCreateUnionRole_ThrowsException_WhenSchemaGrantsExist
    it "throws exception when schema grants exist" do
      role = Java::MondrianOlap::MondrianDef::Role.new
      role.schemaGrants = [Java::MondrianOlap::MondrianDef::SchemaGrant.new].to_java(
        Java::MondrianOlap::MondrianDef::SchemaGrant
      )
      role.union = Java::MondrianOlap::MondrianDef::Union.new

      schema = create_schema
      error = assert_raises(Java::MondrianOlap::MondrianException) do
        invoke_schema_method(
          schema, "createUnionRole",
          [Java::MondrianOlap::MondrianDef::Role.java_class],
          role
        )
      end

      expected_message = Java::MondrianResource::MondrianResource.instance.RoleUnionGrants.ex.getMessage
      assert_equal expected_message, error.getMessage
    end

    # Java: RolapSchemaTest#testCreateUnionRole_ThrowsException_WhenRoleNameIsUnknown
    it "throws exception when role name is unknown" do
      role_name = "non-existing role name"
      usage = Java::MondrianOlap::MondrianDef::RoleUsage.new
      usage.roleName = role_name

      role = Java::MondrianOlap::MondrianDef::Role.new
      role.union = Java::MondrianOlap::MondrianDef::Union.new
      role.union.roleUsages = [usage].to_java(Java::MondrianOlap::MondrianDef::RoleUsage)

      schema = create_schema
      error = assert_raises(Java::MondrianOlap::MondrianException) do
        invoke_schema_method(
          schema, "createUnionRole",
          [Java::MondrianOlap::MondrianDef::Role.java_class],
          role
        )
      end

      expected_message = Java::MondrianResource::MondrianResource.instance.UnknownRole.ex(role_name).getMessage
      assert_equal expected_message, error.getMessage
    end
  end

  describe "handleSchemaGrant" do
    # Java: RolapSchemaTest#testHandleSchemaGrant
    it "grants schema access and processes cube grants" do
      schema = create_schema

      # Create two cubes and register them in the schema so handleCubeGrant can find them.
      # The Java test used spy + doNothing to skip handleCubeGrant, then verified
      # it was called twice. We verify handleCubeGrant is invoked for each cube grant
      # by checking that role.getAccess returns the granted access for each cube.
      cube1 = create_and_register_cube(schema, "cube1")
      cube2 = create_and_register_cube(schema, "cube2")

      cube_grant1 = Java::MondrianOlap::MondrianDef::CubeGrant.new
      cube_grant1.cube = "cube1"
      cube_grant1.access = Java::MondrianOlap::Access::CUSTOM.toString
      cube_grant1.dimensionGrants = [].to_java(Java::MondrianOlap::MondrianDef::DimensionGrant)
      cube_grant1.hierarchyGrants = [].to_java(Java::MondrianOlap::MondrianDef::HierarchyGrant)

      cube_grant2 = Java::MondrianOlap::MondrianDef::CubeGrant.new
      cube_grant2.cube = "cube2"
      cube_grant2.access = Java::MondrianOlap::Access::CUSTOM.toString
      cube_grant2.dimensionGrants = [].to_java(Java::MondrianOlap::MondrianDef::DimensionGrant)
      cube_grant2.hierarchyGrants = [].to_java(Java::MondrianOlap::MondrianDef::HierarchyGrant)

      grant = Java::MondrianOlap::MondrianDef::SchemaGrant.new
      grant.access = Java::MondrianOlap::Access::CUSTOM.toString
      grant.cubeGrants = [cube_grant1, cube_grant2].to_java(Java::MondrianOlap::MondrianDef::CubeGrant)

      role = Java::MondrianOlap::RoleImpl.new

      invoke_schema_method(
        schema, "handleSchemaGrant",
        [Java::MondrianOlap::RoleImpl.java_class, Java::MondrianOlap::MondrianDef::SchemaGrant.java_class],
        role, grant
      )

      assert_equal Java::MondrianOlap::Access::CUSTOM, role.getAccess(schema)
      # Verify handleCubeGrant was invoked for each cube grant
      assert_equal Java::MondrianOlap::Access::CUSTOM, role.getAccess(cube1)
      assert_equal Java::MondrianOlap::Access::CUSTOM, role.getAccess(cube2)
    end
  end

  describe "handleCubeGrant" do
    # Java: RolapSchemaTest#testHandleCubeGrant_ThrowsException_WhenCubeIsUnknown
    it "throws exception when cube is unknown" do
      schema = create_schema

      grant = Java::MondrianOlap::MondrianDef::CubeGrant.new
      grant.cube = "cube"

      error = assert_raises(Java::MondrianOlap::MondrianException) do
        invoke_schema_method(
          schema, "handleCubeGrant",
          [Java::MondrianOlap::RoleImpl.java_class, Java::MondrianOlap::MondrianDef::CubeGrant.java_class],
          Java::MondrianOlap::RoleImpl.new, grant
        )
      end

      assert_includes error.getMessage, grant.cube
    end

    # Java: RolapSchemaTest#testHandleCubeGrant_GrantsCubeDimensionsAndHierarchies
    it "grants cube, dimension, and hierarchy access" do
      schema = create_schema

      # Create a RolapCube via Unsafe and configure it
      cube = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapCube.java_class)
      set_java_field(cube, "schema", schema)
      set_java_field(cube, "name", "cube", Java::MondrianOlap::CubeBase.java_class)
      set_java_field(cube, "uniqueName", "[cube]", Java::MondrianOlap::CubeBase.java_class)

      # Register the cube in the schema's mapNameToCube
      map_name_to_cube = get_java_field(schema, "mapNameToCube")
      map_name_to_cube.put(Java::MondrianOlap::Util.normalizeName("cube"), cube)

      # Create a dimension via Unsafe and set required fields for hashCode/equals
      dimension = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapDimension.java_class)
      set_java_field(dimension, "uniqueName", "[dimension]", Java::MondrianOlap::DimensionBase.java_class)
      set_java_field(dimension, "dimensionType", Java::MondrianOlap::DimensionType::StandardDimension,
                     Java::MondrianOlap::DimensionBase.java_class)

      # Create a hierarchy with levels for the hierarchy grant
      hierarchy = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapHierarchy.java_class)
      set_java_field(hierarchy, "uniqueName", "[hierarchy]", Java::MondrianOlap::HierarchyBase.java_class)
      level = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapLevel.java_class)
      set_java_field(level, "uniqueName", "[hierarchy].[level]", Java::MondrianOlap::LevelBase.java_class)
      set_java_field(level, "hierarchy", hierarchy, Java::MondrianOlap::LevelBase.java_class)
      set_java_field(level, "depth", java.lang.Integer.new(0), Java::MondrianOlap::LevelBase.java_class)
      set_java_field(hierarchy, "levels", [level].to_java(Java::MondrianOlap::Level),
                     Java::MondrianOlap::HierarchyBase.java_class)
      hier_dimension = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapDimension.java_class)
      set_java_field(hier_dimension, "uniqueName", "[hier_dim]", Java::MondrianOlap::DimensionBase.java_class)
      set_java_field(hier_dimension, "dimensionType", Java::MondrianOlap::DimensionType::StandardDimension,
                     Java::MondrianOlap::DimensionBase.java_class)
      set_java_field(hierarchy, "dimension", hier_dimension, Java::MondrianOlap::HierarchyBase.java_class)

      # Create a SchemaReader proxy that returns the correct element based on category.
      # Category.Dimension = 2, Category.Hierarchy = 3
      schema_reader_handler = proc do |_proxy, method, args|
        case method.getName
        when "withLocus"
          _proxy
        when "lookupCompound"
          category = args && args.length >= 4 ? args[3] : nil
          if category == 3  # Category.Hierarchy
            hierarchy
          else
            dimension
          end
        else
          nil
        end
      end

      schema_reader_proxy = java.lang.reflect.Proxy.newProxyInstance(
        Java::MondrianOlap::SchemaReader.java_class.getClassLoader,
        [Java::MondrianOlap::SchemaReader.java_class].to_java(java.lang.Class),
        schema_reader_handler
      )

      # Pre-set the cube's cached schemaReader field so getSchemaReader(null) returns our proxy
      set_java_field(cube, "schemaReader", schema_reader_proxy)

      # Build the grants
      dimension_grant = Java::MondrianOlap::MondrianDef::DimensionGrant.new
      dimension_grant.dimension = "dimension"
      dimension_grant.access = Java::MondrianOlap::Access::NONE.toString

      # Build a hierarchy grant to verify handleHierarchyGrant is invoked.
      # The Java test used doNothing on handleHierarchyGrant and verified it was called once.
      # We pass a real hierarchy grant and verify the resulting access on the hierarchy.
      hierarchy_grant = Java::MondrianOlap::MondrianDef::HierarchyGrant.new
      hierarchy_grant.hierarchy = "hierarchy"
      hierarchy_grant.access = Java::MondrianOlap::Access::ALL.toString
      hierarchy_grant.rollupPolicy = Java::MondrianOlap::Role::RollupPolicy::FULL.toString
      hierarchy_grant.memberGrants = [].to_java(Java::MondrianOlap::MondrianDef::MemberGrant)

      grant = Java::MondrianOlap::MondrianDef::CubeGrant.new
      grant.cube = "cube"
      grant.access = Java::MondrianOlap::Access::CUSTOM.toString
      grant.dimensionGrants = [dimension_grant].to_java(Java::MondrianOlap::MondrianDef::DimensionGrant)
      grant.hierarchyGrants = [hierarchy_grant].to_java(Java::MondrianOlap::MondrianDef::HierarchyGrant)

      role = Java::MondrianOlap::RoleImpl.new

      invoke_schema_method(
        schema, "handleCubeGrant",
        [Java::MondrianOlap::RoleImpl.java_class, Java::MondrianOlap::MondrianDef::CubeGrant.java_class],
        role, grant
      )

      assert_equal Java::MondrianOlap::Access::CUSTOM, role.getAccess(cube)
      assert_equal Java::MondrianOlap::Access::NONE, role.getAccess(dimension)
      # Verify handleHierarchyGrant was invoked for the hierarchy grant
      assert_equal Java::MondrianOlap::Access::ALL, role.getAccess(hierarchy)
    end
  end

  describe "handleHierarchyGrant" do
    # Java: RolapSchemaTest#testHandleHierarchyGrant_ValidMembers
    it "grants hierarchy and member access for valid members" do
      with_properties(IgnoreInvalidMembers: true) do
        do_test_handle_hierarchy_grant(Java::MondrianOlap::Access::CUSTOM, Java::MondrianOlap::Access::ALL)
      end
    end

    # Java: RolapSchemaTest#testHandleHierarchyGrant_NoValidMembers
    it "grants NONE access when no valid members found" do
      with_properties(IgnoreInvalidMembers: true) do
        do_test_handle_hierarchy_grant(Java::MondrianOlap::Access::NONE, nil)
      end
    end
  end

  describe "RolapStarRegistry" do
    # Java: RolapSchemaTest#testEmptyRolapStarRegistryCreatedForTheNewSchema
    it "creates empty registry for a new schema" do
      schema = create_schema
      registry = schema.getRolapStarRegistry
      refute_nil registry
      assert_equal true, registry.getStars.isEmpty
    end

    # Java: RolapSchemaTest#testGetOrCreateStar_StarCreatedAndUsed
    it "caches star and retrieves it on subsequent lookups" do
      skip "FIXME BY SONNET: The Java test verifies both the cache-miss path (makeRolapStar called once on first getOrCreateStar) and the cache-hit path (makeRolapStar not called again on second getOrCreateStar). The Ruby test only covers the cache-hit path by pre-populating the stars map directly, leaving the cache-miss/star-creation path untested. makeRolapStar requires a real database connection, so a different approach (e.g. an integration test that connects to FoodMart and loads a cube) is needed to test the creation path."
      schema = create_schema
      fact_xml = <<~XML.strip
        <Table name="sales_fact_1997" alias="TableAlias">
         <SQL dialect="mysql">
             `TableAlias`.`promotion_id` = 112
         </SQL>
        </Table>
      XML
      fact = Java::MondrianOlap::MondrianDef::Table.new(wrap_xml(fact_xml))
      rolap_star_key = Java::MondrianRolap::RolapUtil.makeRolapStarKey(fact)

      # Create a RolapStar via Unsafe to pre-populate the registry cache.
      # The Java test used Mockito spy on makeRolapStar to intercept star creation
      # and then called getOrCreateStar to test both cache-miss and cache-hit paths.
      # We cannot replicate the cache-miss path because makeRolapStar requires a
      # database connection, so we pre-populate the cache and call getOrCreateStar
      # to test the cache-hit path (star lookup by key).
      star_mock = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapStar.java_class)

      registry = schema.getRolapStarRegistry
      stars_map = get_java_field(registry, "stars")
      stars_map.put(java.util.ArrayList.new(rolap_star_key), star_mock)

      # Call getOrCreateStar via reflection (package-private method)
      actual_star = invoke_registry_get_or_create_star(registry, fact)
      assert_same star_mock, actual_star
      assert_equal 1, registry.getStars.size

      # Second getOrCreateStar returns the same cached star
      actual_star2 = invoke_registry_get_or_create_star(registry, fact)
      assert_same star_mock, actual_star2
      assert_equal 1, registry.getStars.size

      # Also verify getStar retrieves the same star by key
      assert_same star_mock, registry.getStar(rolap_star_key)
    end

    # Java: RolapSchemaTest#testGetStarFromRegistryByStarKey
    it "retrieves star from registry by star key" do
      schema = create_schema
      fact_xml = <<~XML.strip
        <Table name="sales_fact_1997" alias="TableAlias">
         <SQL dialect="mysql">
             `TableAlias`.`promotion_id` = 112
         </SQL>
        </Table>
      XML
      fact = Java::MondrianOlap::MondrianDef::Table.new(wrap_xml(fact_xml))
      rolap_star_key = Java::MondrianRolap::RolapUtil.makeRolapStarKey(fact)

      star_mock = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapStar.java_class)

      # Pre-populate via the stars map and retrieve via getOrCreateStar
      registry = schema.getRolapStarRegistry
      stars_map = get_java_field(registry, "stars")
      stars_map.put(java.util.ArrayList.new(rolap_star_key), star_mock)

      # Use getOrCreateStar to retrieve (cache hit) and verify via schema.getStar
      actual_star = invoke_registry_get_or_create_star(registry, fact)
      assert_same star_mock, actual_star
      assert_same star_mock, schema.getStar(rolap_star_key)
    end

    # Java: RolapSchemaTest#testGetStarFromRegistryByFactTableName
    it "retrieves star from registry by fact table name" do
      schema = create_schema
      fact_xml = '<Table name="sales_fact_1997" alias="TableAlias"/>'
      fact = Java::MondrianOlap::MondrianDef::Table.new(wrap_xml(fact_xml))

      star_mock = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapStar.java_class)

      # Pre-populate via the stars map and retrieve via getOrCreateStar
      registry = schema.getRolapStarRegistry
      stars_map = get_java_field(registry, "stars")
      rolap_star_key = Java::MondrianRolap::RolapUtil.makeRolapStarKey(fact)
      stars_map.put(java.util.ArrayList.new(rolap_star_key), star_mock)

      # Use getOrCreateStar to verify the star is found by key
      actual_star = invoke_registry_get_or_create_star(registry, fact)
      assert_same star_mock, actual_star
      # Also verify lookup by fact table name works
      assert_same star_mock, schema.getStar(fact.getAlias)
    end
  end

  private

  # Invokes the package-private getOrCreateStar method on a RolapStarRegistry via reflection.
  def invoke_registry_get_or_create_star(registry, fact)
    relation_class = find_java_class("mondrian.olap.MondrianDef$Relation")
    method = find_method(registry, "getOrCreateStar", [relation_class])
    method.invoke(registry, fact)
  rescue java.lang.reflect.InvocationTargetException => e
    raise e.cause
  end

  # Mirrors the Java doTestHandleHierarchyGrant helper.
  # Creates mock hierarchy, level, dimension, and member objects via Unsafe,
  # then invokes handleHierarchyGrant and checks the resulting access.
  def do_test_handle_hierarchy_grant(expected_hierarchy_access, expected_member_access)
    schema = create_schema
    cube = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapCube.java_class)
    set_java_field(cube, "schema", schema)
    role = Java::MondrianOlap::RoleImpl.new

    # Create hierarchy, level, dimension, and optionally member via Unsafe
    hierarchy = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapHierarchy.java_class)
    set_java_field(hierarchy, "uniqueName", "[hierarchy]", Java::MondrianOlap::HierarchyBase.java_class)

    level = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapLevel.java_class)
    set_java_field(level, "uniqueName", "[hierarchy].[level]", Java::MondrianOlap::LevelBase.java_class)

    # Set level's hierarchy reference (field is on LevelBase)
    set_java_field(level, "hierarchy", hierarchy, Java::MondrianOlap::LevelBase.java_class)
    # Set level depth (needed by role.grant for level depth checks)
    set_java_field(level, "depth", java.lang.Integer.new(0), Java::MondrianOlap::LevelBase.java_class)

    # Set hierarchy's levels array (field is on HierarchyBase)
    levels_array = [level].to_java(Java::MondrianOlap::Level)
    set_java_field(hierarchy, "levels", levels_array, Java::MondrianOlap::HierarchyBase.java_class)

    # Create dimension and link to hierarchy (field is on HierarchyBase)
    dimension = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapDimension.java_class)
    set_java_field(dimension, "uniqueName", "[dimension]", Java::MondrianOlap::DimensionBase.java_class)
    set_java_field(dimension, "dimensionType", Java::MondrianOlap::DimensionType::StandardDimension,
                   Java::MondrianOlap::DimensionBase.java_class)
    set_java_field(hierarchy, "dimension", dimension, Java::MondrianOlap::HierarchyBase.java_class)

    # Create member if expected
    member = nil
    if expected_member_access
      member = UNSAFE_RS.allocateInstance(Java::MondrianRolap::RolapMemberBase.java_class)
      # Set the level on the member (field is on MemberBase); member.getHierarchy() delegates to level.getHierarchy()
      set_java_field(member, "level", level, Java::MondrianOlap::MemberBase.java_class)
      set_java_field(member, "uniqueName", "[hierarchy].[member]", Java::MondrianOlap::MemberBase.java_class)
      # Initialize mapPropertyNameToValue (needed by getName() -> getPropertyValue -> getPropertyFromMap)
      set_java_field(member, "mapPropertyNameToValue", java.util.concurrent.ConcurrentHashMap.new)
    end

    # Build SchemaReader proxy
    schema_reader_handler = proc do |proxy, method, args|
      case method.getName
      when "withLocus"
        proxy
      when "lookupCompound"
        hierarchy
      when "getMemberByUniqueName"
        member
      else
        nil
      end
    end

    schema_reader_proxy = java.lang.reflect.Proxy.newProxyInstance(
      Java::MondrianOlap::SchemaReader.java_class.getClassLoader,
      [Java::MondrianOlap::SchemaReader.java_class].to_java(java.lang.Class),
      schema_reader_handler
    )

    # Build the HierarchyGrant
    member_grant = Java::MondrianOlap::MondrianDef::MemberGrant.new
    member_grant.access = Java::MondrianOlap::Access::ALL.toString
    member_grant.member = "member"

    grant = Java::MondrianOlap::MondrianDef::HierarchyGrant.new
    grant.access = Java::MondrianOlap::Access::CUSTOM.toString
    grant.rollupPolicy = Java::MondrianOlap::Role::RollupPolicy::FULL.toString
    grant.hierarchy = "hierarchy"
    grant.memberGrants = [member_grant].to_java(Java::MondrianOlap::MondrianDef::MemberGrant)

    invoke_schema_method(
      schema, "handleHierarchyGrant",
      [
        Java::MondrianOlap::RoleImpl.java_class,
        Java::MondrianRolap::RolapCube.java_class,
        Java::MondrianOlap::SchemaReader.java_class,
        Java::MondrianOlap::MondrianDef::HierarchyGrant.java_class
      ],
      role, cube, schema_reader_proxy, grant
    )

    assert_equal expected_hierarchy_access, role.getAccess(hierarchy)
    if expected_member_access
      assert_equal expected_member_access, role.getAccess(member)
    end
  end
end
