# frozen_string_literal: true

module SchemaHelper
  FOODMART_SCHEMA = File.read(
    File.join(File.expand_path('../..', __dir__), 'demo/FoodMart.xml')
  )

  # Insertion points for each element type within a cube definition.
  # Each entry maps to the XML tags to insert before, in order of precedence.
  # Elements without an existing tag (calculated members, named sets) fall back
  # to inserting before the closing </Cube> tag.
  CUBE_ELEMENT_TAGS = {
    dimensions:         {tags: %w[Dimension DimensionUsage], fallback_to_end: false},
    measures:           {tags: %w[Measure VirtualCubeMeasure], fallback_to_end: false},
    calculated_members: {tags: %w[CalculatedMember], fallback_to_end: true},
    named_sets:         {tags: %w[NamedSet], fallback_to_end: true}
  }.freeze

  # Create a connection with a modified FoodMart schema.
  # Mirrors Java's TestContext.createSubstitutingCube().
  #
  #   olap = connection_with_modified_cube("Sales",
  #     dimensions: '<Dimension name="MyDim" foreignKey="store_id">...</Dimension>',
  #     measures:   '<Measure name="MyMeasure" aggregator="sum" column="unit_sales"/>',
  #     calculated_members: '<CalculatedMember name="Profit" dimension="Measures">...</CalculatedMember>',
  #     named_sets: '<NamedSet name="TopStores">...</NamedSet>'
  #   )
  def connection_with_modified_cube(cube_name, **elements)
    schema = schema_with_modified_cube(FOODMART_SCHEMA, cube_name, **elements)

    params = CONNECTION_PARAMS.merge(catalog_content: schema)
    params.delete(:catalog)
    Mondrian::OLAP::Connection.create(params)
  end

  private

  def schema_with_modified_cube(original_schema, cube_name, **elements)
    schema = original_schema.dup
    cube_start = schema.index("<Cube name=\"#{cube_name}\"") ||
                 schema.index("<VirtualCube name=\"#{cube_name}\"")
    raise "Cube '#{cube_name}' not found in schema" unless cube_start

    cube_tag = schema[cube_start..cube_start + 20].include?("VirtualCube") ? "VirtualCube" : "Cube"
    cube_end = schema.index("</#{cube_tag}>", cube_start)

    CUBE_ELEMENT_TAGS.each do |key, config|
      fragment = elements[key]
      next unless fragment

      insertion_position = find_first_tag(schema, cube_start, cube_end, config[:tags])
      insertion_position ||= cube_end if config[:fallback_to_end]
      next unless insertion_position

      schema = schema[0...insertion_position] + fragment + "\n" + schema[insertion_position..]
      cube_end += fragment.length + 1
    end

    schema
  end

  def find_first_tag(schema, start_position, end_position, tag_names)
    tag_names.filter_map do |tag|
      position = schema.index("<#{tag} ", start_position)
      position if position && position < end_position
    end.min
  end
end
