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

# Java: mondrian/rolap/RolapCubeDimensionTest.java
describe "RolapCubeDimension" do
  # Access Unsafe for allocating Java objects without calling constructors
  unsafe_field = java.lang.Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe")
  unsafe_field.accessible = true
  UNSAFE_RCD = unsafe_field.get(nil)

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

  # Creates a RolapCubeDimension via Unsafe (bypasses constructor).
  def create_rolap_cube_dimension
    UNSAFE_RCD.allocateInstance(Java::MondrianRolap::RolapCubeDimension.java_class)
  end

  # Creates a RolapSchema via Unsafe and initializes its mapNameToCube field.
  # When recording: true, wraps mapNameToCube with a recording proxy that tracks
  # all method calls. Returns [schema, calls] where calls is an array of method
  # names invoked on the map (used to verify lookupCube was or was not called).
  def create_schema_with_cubes(cube_map = {}, recording: false)
    schema = UNSAFE_RCD.allocateInstance(Java::MondrianRolap::RolapSchema.java_class)
    map = java.util.HashMap.new
    cube_map.each do |name, cube|
      normalized = Java::MondrianOlap::Util.normalizeName(name)
      map.put(normalized, cube)
    end
    if recording
      calls = []
      recording_map = java.lang.reflect.Proxy.newProxyInstance(
        java.util.Map.java_class.getClassLoader,
        [java.util.Map.java_class].to_java(java.lang.Class),
        ->(_, method, args) {
          calls << method.getName
          method.invoke(map, args)
        }
      )
      set_java_field(schema, "mapNameToCube", recording_map)
      [schema, calls]
    else
      set_java_field(schema, "mapNameToCube", map)
      schema
    end
  end

  # Creates a RolapCube via Unsafe (bypasses constructor).
  def create_mock_cube
    UNSAFE_RCD.allocateInstance(Java::MondrianRolap::RolapCube.java_class)
  end

  # Invokes the package-private lookupFactCube method via reflection.
  def invoke_lookup_fact_cube(rcd, cube_dim, schema)
    method = Java::MondrianRolap::RolapCubeDimension.java_class.getDeclaredMethod(
      "lookupFactCube",
      [Java::MondrianOlap::MondrianDef::CubeDimension.java_class,
       Java::MondrianRolap::RolapSchema.java_class].to_java(java.lang.Class)
    )
    method.accessible = true
    method.invoke(rcd, cube_dim, schema)
  end

  public

  # Java: RolapCubeDimensionTest#testLookupCube_null
  it "lookupFactCube returns nil when both arguments are null" do
    rcd = create_rolap_cube_dimension

    result = invoke_lookup_fact_cube(rcd, nil, nil)

    assert_nil result
  end

  # Java: RolapCubeDimensionTest#testLookupCube_notVirtual
  it "lookupFactCube returns nil for a non-virtual cube dimension" do
    rcd = create_rolap_cube_dimension
    cube_dim = Java::MondrianOlap::MondrianDef::Dimension.new
    schema, map_calls = create_schema_with_cubes(recording: true)

    result = invoke_lookup_fact_cube(rcd, cube_dim, schema)

    assert_nil result
    # Verify the instanceof VirtualCubeDimension guard works: lookupCube should
    # never be called for a non-virtual dimension, so the map should not be accessed.
    assert_empty map_calls.select { |name| name == "get" },
      "Expected lookupCube to not be called, but mapNameToCube.get was invoked"
  end

  # Java: RolapCubeDimensionTest#testLookupCube_noSuchCube
  it "lookupFactCube returns nil when virtual cube dimension references a non-existent cube" do
    rcd = create_rolap_cube_dimension
    cube_dim = Java::MondrianOlap::MondrianDef::VirtualCubeDimension.new
    cube_dim.cubeName = "TheCubeName"
    schema, map_calls = create_schema_with_cubes(recording: true)

    result = invoke_lookup_fact_cube(rcd, cube_dim, schema)

    assert_nil result
    # Verify the VirtualCubeDimension path invokes lookupCube (equivalent to
    # Mockito.verify(schema).lookupCube(cubeName) in the Java test).
    assert_includes map_calls, "get",
      "Expected lookupCube to be called, but mapNameToCube.get was not invoked"
  end

  # Java: RolapCubeDimensionTest#testLookupCube_found
  it "lookupFactCube returns the fact cube when virtual cube dimension references an existing cube" do
    rcd = create_rolap_cube_dimension
    cube_dim = Java::MondrianOlap::MondrianDef::VirtualCubeDimension.new
    cube_dim.cubeName = "TheCubeName"
    fact_cube = create_mock_cube
    schema = create_schema_with_cubes({"TheCubeName" => fact_cube})

    result = invoke_lookup_fact_cube(rcd, cube_dim, schema)

    assert_same fact_cube, result
  end
end
