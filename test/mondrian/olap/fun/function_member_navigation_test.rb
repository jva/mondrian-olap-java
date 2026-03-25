# This software is subject to the terms of the Eclipse Public License v1.0
# Agreement, available at the following URL:
# http://www.eclipse.org/legal/epl-v10.html.
# You must accept the terms of that agreement to use this software.
#
# Copyright (C) 2003-2005 Julian Hyde
# Copyright (C) 2005-2021 Hitachi Vantara and others
# Copyright (C) 2026 eazyBI
# All Rights Reserved.

# frozen_string_literal: true

require_relative "../../../test_helper"

# Java: mondrian/olap/fun/FunctionTest.java
describe "FunctionTest member navigation" do
  before(:all) do
    create_olap_connection
  end

  describe "Ordinal" do
    # Java: FunctionTest#testOrdinal
    it "returns ordinal of member in ragged hierarchy" do
      # Vatican is at level 1
      assert_expression_returns @olap,
        "[Store].[All Stores].[Vatican].ordinal", "1",
        cube: "Sales Ragged"

      # Washington is at level 3
      assert_expression_returns @olap,
        "[Store].[All Stores].[USA].[Washington].ordinal", "3",
        cube: "Sales Ragged"
    end
  end

  describe "Cousin" do
    # Java: FunctionTest#testCousin1
    it "finds cousin of Q4 in 1998" do
      assert_axis_returns @olap,
        "Cousin([1997].[Q4],[1998])",
        "[Time].[1998].[Q4]"
    end

    # Java: FunctionTest#testCousin2
    it "finds cousin of month 12 in Q1 1998" do
      assert_axis_returns @olap,
        "Cousin([1997].[Q4].[12],[1998].[Q1])",
        "[Time].[1998].[Q1].[3]"
    end

    # Java: FunctionTest#testCousinOverrun
    it "returns null when cousin position overruns children" do
      # CA has more cities than OR
      assert_axis_returns @olap,
        "Cousin([Customers].[USA].[CA].[San Jose], [Customers].[USA].[OR])",
        ""
    end

    # Java: FunctionTest#testCousinThreeDown
    it "finds cousin three levels down" do
      # Barbara Combs is the 6th child
      # of the 4th child (Berkeley)
      # of the 1st child (CA)
      # of USA
      # Annmarie Hill is the 6th child
      # of the 4th child (Tixapan)
      # of the 1st child (DF)
      # of Mexico
      assert_axis_returns @olap,
        "Cousin([Customers].[USA].[CA].[Berkeley].[Barbara Combs], [Customers].[Mexico])",
        "[Customers].[Mexico].[DF].[Tixapan].[Annmarie Hill]"
    end

    # Java: FunctionTest#testCousinSameLevel
    it "finds cousin at same level" do
      assert_axis_returns @olap,
        "Cousin([Gender].[M], [Gender].[F])",
        "[Gender].[F]"
    end

    # Java: FunctionTest#testCousinHigherLevel
    it "returns null when ancestor is at higher level than member" do
      assert_axis_returns @olap,
        "Cousin([Time].[1997], [Time].[1998].[Q1])",
        ""
    end

    # Java: FunctionTest#testCousinWrongHierarchy
    it "raises error when members are from different hierarchies" do
      error = assert_raises(Mondrian::OLAP::Error) do
        @olap.execute("SELECT {Cousin([Time].[1997], [Gender].[M])} ON COLUMNS FROM Sales")
      end
      assert_match(
        /The member arguments to the Cousin function must be from the same hierarchy/,
        root_cause_message(error)
      )
    end
  end

  private

  def root_cause_message(exception)
    cause = exception
    cause = cause.cause while cause.cause && cause.cause != cause
    cause.message
  end

  public

  describe "Parent" do
    # Java: FunctionTest#testParent
    it "returns parent of a member" do
      assert_axis_returns @olap,
        "{[Store].[USA].[CA].Parent}",
        "[Store].[USA]"

      # root member has null parent
      assert_axis_returns @olap,
        "{[Store].[All Stores].Parent}",
        ""

      # parent of null member is null
      assert_axis_returns @olap,
        "{[Store].[All Stores].Parent.Parent}",
        ""
    end

    # Java: FunctionTest#testParentPC
    it "returns parent in parent-child hierarchy" do
      assert_axis_returns @olap,
        "[Employees].Parent",
        "",
        cube: "HR"

      assert_axis_returns @olap,
        "[Employees].[Sheri Nowmer].Parent",
        "[Employees].[All Employees]",
        cube: "HR"

      assert_axis_returns @olap,
        "[Employees].[Sheri Nowmer].[Derrick Whelply].Parent",
        "[Employees].[Sheri Nowmer]",
        cube: "HR"

      assert_axis_returns @olap,
        "[Employees].Members.Item(3)",
        "[Employees].[Sheri Nowmer].[Derrick Whelply].[Beverly Baker]",
        cube: "HR"

      assert_axis_returns @olap,
        "[Employees].Members.Item(3).Parent",
        "[Employees].[Sheri Nowmer].[Derrick Whelply]",
        cube: "HR"

      assert_axis_returns @olap,
        "[Employees].AllMembers.Item(3).Parent",
        "[Employees].[Sheri Nowmer].[Derrick Whelply]",
        cube: "HR"

      # Ascendants(<Member>) applied to parent-child hierarchy accessed via
      # <Level>.Members
      assert_axis_returns @olap,
        "Ascendants([Employees].Members.Item(73))",
        "[Employees].[Sheri Nowmer].[Derrick Whelply].[Beverly Baker].[Jacqueline Wyllie].[Ralph Mccoy].[Bertha Jameson].[James Bailey]\n" \
        "[Employees].[Sheri Nowmer].[Derrick Whelply].[Beverly Baker].[Jacqueline Wyllie].[Ralph Mccoy].[Bertha Jameson]\n" \
        "[Employees].[Sheri Nowmer].[Derrick Whelply].[Beverly Baker].[Jacqueline Wyllie].[Ralph Mccoy]\n" \
        "[Employees].[Sheri Nowmer].[Derrick Whelply].[Beverly Baker].[Jacqueline Wyllie]\n" \
        "[Employees].[Sheri Nowmer].[Derrick Whelply].[Beverly Baker]\n" \
        "[Employees].[Sheri Nowmer].[Derrick Whelply]\n" \
        "[Employees].[Sheri Nowmer]\n" \
        "[Employees].[All Employees]",
        cube: "HR"
    end
  end

  describe "FirstChild" do
    # Java: FunctionTest#testFirstChildFirstInLevel
    it "returns first child of Q4" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q4].FirstChild",
        "[Time].[1997].[Q4].[10]"
    end

    # Java: FunctionTest#testFirstChildAll
    it "returns first child of All Gender" do
      assert_axis_returns @olap,
        "[Gender].[All Gender].FirstChild",
        "[Gender].[F]"
    end

    # Java: FunctionTest#testFirstChildOfChildless
    it "returns null for childless member" do
      assert_axis_returns @olap,
        "[Gender].[All Gender].[F].FirstChild",
        ""
    end
  end

  describe "FirstSibling" do
    # Java: FunctionTest#testFirstSiblingFirstInLevel
    it "returns first sibling when already first" do
      assert_axis_returns @olap,
        "[Gender].[F].FirstSibling",
        "[Gender].[F]"
    end

    # Java: FunctionTest#testFirstSiblingLastInLevel
    it "returns first sibling from last in level" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q4].FirstSibling",
        "[Time].[1997].[Q1]"
    end

    # Java: FunctionTest#testFirstSiblingAll
    it "returns All member as its own first sibling" do
      assert_axis_returns @olap,
        "[Gender].[All Gender].FirstSibling",
        "[Gender].[All Gender]"
    end

    # Java: FunctionTest#testFirstSiblingRoot
    it "returns first sibling among root members" do
      # The [Measures] hierarchy does not have an 'all' member, so
      # [Unit Sales] does not have a parent.
      assert_axis_returns @olap,
        "[Measures].[Store Sales].FirstSibling",
        "[Measures].[Unit Sales]"
    end

    # Java: FunctionTest#testFirstSiblingNull
    it "returns null for first sibling of null member" do
      assert_axis_returns @olap,
        "[Gender].[F].FirstChild.FirstSibling",
        ""
    end
  end

  describe "Lag" do
    # Java: FunctionTest#testLag
    it "lags by 4 months" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q4].[12].Lag(4)",
        "[Time].[1997].[Q3].[8]"
    end

    # Java: FunctionTest#testLagFirstInLevel
    it "returns null when lagging past first in level" do
      assert_axis_returns @olap,
        "[Gender].[F].Lag(1)",
        ""
    end

    # Java: FunctionTest#testLagAll
    it "returns null when lagging All member" do
      assert_axis_returns @olap,
        "[Gender].DefaultMember.Lag(2)",
        ""
    end

    # Java: FunctionTest#testLagRoot
    it "lags from root level" do
      assert_axis_returns @olap,
        "[Time].[1998].Lag(1)",
        "[Time].[1997]"
    end

    # Java: FunctionTest#testLagRootTooFar
    it "returns null when lagging too far past root" do
      assert_axis_returns @olap,
        "[Time].[1998].Lag(2)",
        ""
    end
  end

  describe "LastChild" do
    # Java: FunctionTest#testLastChild
    it "returns last child of Gender" do
      assert_axis_returns @olap,
        "[Gender].LastChild",
        "[Gender].[M]"
    end

    # Java: FunctionTest#testLastChildLastInLevel
    it "returns last child of Q4" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q4].LastChild",
        "[Time].[1997].[Q4].[12]"
    end

    # Java: FunctionTest#testLastChildAll
    it "returns last child of All Gender" do
      assert_axis_returns @olap,
        "[Gender].[All Gender].LastChild",
        "[Gender].[M]"
    end

    # Java: FunctionTest#testLastChildOfChildless
    it "returns null for childless member" do
      assert_axis_returns @olap,
        "[Gender].[M].LastChild",
        ""
    end
  end

  describe "LastSibling" do
    # Java: FunctionTest#testLastSibling
    it "returns last sibling of F" do
      assert_axis_returns @olap,
        "[Gender].[F].LastSibling",
        "[Gender].[M]"
    end

    # Java: FunctionTest#testLastSiblingFirstInLevel
    it "returns last sibling from first in level" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q1].LastSibling",
        "[Time].[1997].[Q4]"
    end

    # Java: FunctionTest#testLastSiblingAll
    it "returns All member as its own last sibling" do
      assert_axis_returns @olap,
        "[Gender].[All Gender].LastSibling",
        "[Gender].[All Gender]"
    end

    # Java: FunctionTest#testLastSiblingRoot
    it "returns last sibling among root members" do
      # The [Time] hierarchy does not have an 'all' member, so
      # [1997], [1998] do not have parents.
      assert_axis_returns @olap,
        "[Time].[1998].LastSibling",
        "[Time].[1998]"
    end

    # Java: FunctionTest#testLastSiblingNull
    it "returns null for last sibling of null member" do
      assert_axis_returns @olap,
        "[Gender].[F].FirstChild.LastSibling",
        ""
    end
  end

  describe "Lead" do
    # Java: FunctionTest#testLead
    it "leads by 4 months" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q2].[4].Lead(4)",
        "[Time].[1997].[Q3].[8]"
    end

    # Java: FunctionTest#testLeadNegative
    it "leads by negative amount" do
      assert_axis_returns @olap,
        "[Gender].[M].Lead(-1)",
        "[Gender].[F]"
    end

    # Java: FunctionTest#testLeadLastInLevel
    it "returns null when leading past last in level" do
      assert_axis_returns @olap,
        "[Gender].[M].Lead(3)",
        ""
    end

    # Java: FunctionTest#testLeadNull
    it "returns null when leading from null member" do
      assert_axis_returns @olap,
        "[Gender].Parent.Lead(1)",
        ""
    end

    # Java: FunctionTest#testLeadZero
    it "returns same member when leading by zero" do
      assert_axis_returns @olap,
        "[Gender].[F].Lead(0)",
        "[Gender].[F]"
    end
  end

  describe "NextMember" do
    # Java: FunctionTest#testBasic2
    it "returns next member of F" do
      assert_axis_returns @olap,
        "[Gender].[F].NextMember",
        "[Gender].[M]"
    end

    # Java: FunctionTest#testFirstInLevel2
    it "returns empty when next member is past last in level" do
      assert_axis_returns @olap,
        "[Gender].[M].NextMember",
        ""
    end

    # Java: FunctionTest#testAll2
    it "returns empty for PrevMember of All (via NextMember context)" do
      # previous to [Gender].[All] is null, so no members are returned
      assert_axis_returns @olap,
        "[Gender].PrevMember",
        ""
    end
  end

  describe "Parent via query" do
    # Java: FunctionTest#testBasic5
    it "returns parent of Drink" do
      assert_axis_returns @olap,
        "[Product].[All Products].[Drink].Parent",
        "[Product].[All Products]"
    end

    # Java: FunctionTest#testFirstInLevel5
    it "returns parent of month 4" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q2].[4].Parent",
        "[Time].[1997].[Q2]"
    end

    # Java: FunctionTest#testAll5
    it "returns parent of Q2" do
      assert_axis_returns @olap,
        "[Time].[1997].[Q2].Parent",
        "[Time].[1997]"
    end
  end

  describe "PrevMember" do
    # Java: FunctionTest#testBasic
    it "returns previous member of M" do
      assert_axis_returns @olap,
        "[Gender].[M].PrevMember",
        "[Gender].[F]"
    end

    # Java: FunctionTest#testFirstInLevel
    it "returns empty when prev member is past first in level" do
      assert_axis_returns @olap,
        "[Gender].[F].PrevMember",
        ""
    end

    # Java: FunctionTest#testAll
    it "returns empty for PrevMember of All" do
      # previous to [Gender].[All] is null, so no members are returned
      assert_axis_returns @olap,
        "[Gender].PrevMember",
        ""
    end
  end

  describe "Siblings" do
    # Java: FunctionTest#testSiblingsA
    it "returns siblings of 1997" do
      assert_axis_returns @olap,
        "{[Time].[1997].Siblings}",
        "[Time].[1997]\n[Time].[1998]"
    end

    # Java: FunctionTest#testSiblingsB
    it "returns siblings of All Stores" do
      assert_axis_returns @olap,
        "{[Store].Siblings}",
        "[Store].[All Stores]"
    end

    # Java: FunctionTest#testSiblingsC
    it "returns siblings of CA" do
      assert_axis_returns @olap,
        "{[Store].[USA].[CA].Siblings}",
        "[Store].[USA].[CA]\n[Store].[USA].[OR]\n[Store].[USA].[WA]"
    end

    # Java: FunctionTest#testSiblingsD
    it "returns empty siblings for null member" do
      # The null member has no siblings -- not even itself
      assert_axis_returns @olap,
        "{[Gender].Parent.Siblings}",
        ""

      assert_expression_returns @olap,
        "count ([Gender].parent.siblings, includeempty)", "0"
    end
  end
end
