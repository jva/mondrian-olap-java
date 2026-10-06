# frozen_string_literal: true

# InvocationHandler for the package-private RolapNative.Listener interface.
# Tracks whether native evaluation was used (foundEvaluator) and whether
# it executed SQL (executingSql).
class NativeListenerHandler
  include java.lang.reflect.InvocationHandler

  attr_reader :evaluator_found
  attr_accessor :execute_sql

  def initialize
    @evaluator_found = false
    @execute_sql = false
  end

  def invoke(_proxy, method, _args)
    case method.getName
    when "foundEvaluator" then @evaluator_found = true
    when "executingSql" then @execute_sql = true
    end
    nil
  end
end

# Reflection helpers for the package-private RolapNativeRegistry API.
# Mirrors the native evaluation checks of Java's BatchTestCase.
module NativeRegistryHelper
  def invoke_method(object, method_name, param_types = [], *args)
    cls = object.getClass
    method = nil
    while cls
      begin
        method = cls.getDeclaredMethod(method_name, param_types.to_java(java.lang.Class))
        break
      rescue java.lang.NoSuchMethodException
        cls = cls.getSuperclass
      end
    end
    raise "Method #{method_name} not found on #{object.getClass.getName}" unless method
    method.setAccessible(true)
    args.empty? ? method.invoke(object) : method.invoke(object, *args)
  end

  def get_native_registry(olap)
    schema = olap.raw_mondrian_connection.getSchema
    invoke_method(schema, "getNativeRegistry")
  end

  def set_native_enabled(registry, enabled)
    invoke_method(registry, "setEnabled", [java.lang.Boolean::TYPE], enabled)
  end

  def set_native_listener(registry, listener)
    listener_class = java.lang.Class.forName(
      "mondrian.rolap.RolapNative$Listener", true, registry.getClass.getClassLoader
    )
    invoke_method(registry, "setListener", [listener_class], listener)
  end

  def set_native_hard_cache(registry, hard)
    invoke_method(registry, "useHardCache", [java.lang.Boolean::TYPE], hard)
  end

  def create_native_listener(registry)
    class_loader = registry.getClass.getClassLoader
    listener_interface = java.lang.Class.forName(
      "mondrian.rolap.RolapNative$Listener", true, class_loader
    )
    handler = NativeListenerHandler.new
    proxy = java.lang.reflect.Proxy.newProxyInstance(
      class_loader,
      [listener_interface].to_java(java.lang.Class),
      handler
    )
    [proxy, handler]
  end
end
