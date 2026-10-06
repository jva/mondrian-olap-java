# frozen_string_literal: true

module MondrianPropertiesHelper
  # Temporarily set Mondrian properties for the duration of a block.
  # Automatically restores original values on exit.
  #
  #   with_properties(EnableNativeTopCount: false, ExpandNonNative: true) do
  #     result = @olap.execute(mdx)
  #   end
  def with_properties(**properties)
    mondrian_properties = Java::MondrianOlap::MondrianProperties.instance
    original_values = {}

    properties.each do |name, value|
      property = mondrian_properties.public_send(name)
      original_values[name] = property.get
      property.set(value)
    end

    yield
  ensure
    original_values.each do |name, original_value|
      mondrian_properties.public_send(name).set(original_value)
    end
  end

  # Access a specific property for inspection.
  def mondrian_property(name)
    Java::MondrianOlap::MondrianProperties.instance.public_send(name)
  end
end
