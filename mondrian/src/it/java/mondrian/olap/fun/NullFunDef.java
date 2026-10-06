/*
// This software is subject to the terms of the Eclipse Public License v1.0
// Agreement, available at the following URL:
// http://www.eclipse.org/legal/epl-v10.html.
// You must accept the terms of that agreement to use this software.
//
// Copyright (c) 2002-2020 Hitachi Vantara..  All rights reserved.
*/
package mondrian.olap.fun;

import mondrian.calc.Calc;
import mondrian.calc.ExpCompiler;
import mondrian.mdx.ResolvedFunCall;
import mondrian.olap.Exp;
import mondrian.olap.FunDef;
import mondrian.olap.Syntax;
import mondrian.olap.Validator;

import java.io.PrintWriter;

/**
 * Function definition stub for tests that need a {@link FunDef} instance.
 */
public class NullFunDef implements FunDef {
  public NullFunDef() {
  }

  public Syntax getSyntax() {
    return Syntax.Function;
  }

  public String getName() {
    return "";
  }

  public String getDescription() {
    return "";
  }

  public int getReturnCategory() {
    return 0;
  }

  public int[] getParameterCategories() {
    return new int[ 0 ];
  }

  public Exp createCall( Validator validator, Exp[] args ) {
    return null;
  }

  public String getSignature() {
    return "";
  }

  public void unparse( Exp[] args, PrintWriter pw ) {
    //
  }

  public Calc compileCall( ResolvedFunCall call, ExpCompiler compiler ) {
    return null;
  }
}

// End NullFunDef.java
