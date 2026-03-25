# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2002-2017 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/IifFunDefTest.java
describe "IifFunDef" do
  # Minimal Exp stub replacing Mockito mock.
  # Only getType() is meaningful; other methods satisfy the interface contract.
  class self::ExpStub
    include Java::MondrianOlap::Exp

    def initialize(type = nil)
      @type = type
    end

    def getType; @type; end
    def getCategory; 0; end
    def clone; self; end
    def unparse(writer); end
    def accept(visitor); nil; end
  end

  # Minimal ExpCompiler stub replacing Mockito mock.
  # compileAs returns a configurable result; all other methods return nil.
  class self::CompilerStub
    include Java::MondrianCalc::ExpCompiler

    attr_writer :compile_as_result

    def compileAs(expression, type, result_styles); @compile_as_result; end
    def compileBoolean(expression); nil; end
    def compileList(expression, mutable = false); nil; end
    def getEvaluator; nil; end
    def getValidator; nil; end
    def compile(expression); nil; end
    def compileMember(expression); nil; end
    def compileLevel(expression); nil; end
    def compileDimension(expression); nil; end
    def compileHierarchy(expression); nil; end
    def compileInteger(expression); nil; end
    def compileString(expression); nil; end
    def compileDateTime(expression); nil; end
    def compileIter(expression); nil; end
    def compileDouble(expression); nil; end
    def compileTuple(expression); nil; end
    def compileScalar(expression, specific); nil; end
    def registerParameter(parameter); nil; end
    def getAcceptableResultStyles; nil; end
  end

  # Java: IifFunDefTest#testGetResultType
  it "compileCall preserves ResultStyle from set arguments" do
    member_type = Java::MondrianOlapType::MemberType.new(nil, nil, nil, nil)
    set_type = Java::MondrianOlapType::SetType.new(member_type)

    logical_param = self.class::ExpStub.new
    true_case_param = self.class::ExpStub.new(set_type)
    false_case_param = self.class::ExpStub.new

    args = [logical_param, true_case_param, false_case_param].to_java(Java::MondrianOlap::Exp)

    # Build a SetListCalc (the value compileAs will return).
    # The setup compiler's compileList returns nil, matching Mockito default.
    setup_compiler = self.class::CompilerStub.new
    set_list_calc = Java::MondrianOlapFun::SetFunDef::SetListCalc.new(
      true_case_param,
      [true_case_param].to_java(Java::MondrianOlap::Exp),
      setup_compiler,
      Java::MondrianCalc::ResultStyle::LIST_MUTABLELIST
    )

    expected_result_style = set_list_calc.getResultStyle

    # Wire the test compiler so compileAs returns the SetListCalc.
    compiler = self.class::CompilerStub.new
    compiler.compile_as_result = set_list_calc

    field = Java::MondrianOlapFun::IifFunDef.java_class.getDeclaredField("SET_INSTANCE")
    field.setAccessible(true)
    fun_def = field.get(nil)

    call = Java::MondrianMdx::ResolvedFunCall.new(fun_def, args, set_type)

    # Compile the IIF call and verify the result style is preserved.
    calc = fun_def.compileCall(call, compiler)

    refute_nil calc.getResultStyle
    assert_equal expected_result_style, calc.getResultStyle
  end
end
