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
describe "Descendants" do
  before(:all) do
    create_olap_connection
  end

  # Assert that executing an axis expression raises an error whose root cause
  # message includes the given pattern. Mirrors Java's assertAxisThrows.
  def assert_axis_throws(expression, pattern, cube: "Sales")
    mdx = "SELECT {#{expression}} ON COLUMNS FROM [#{cube}]"
    error = assert_raises(Mondrian::OLAP::Error) { @olap.execute(mdx) }
    assert error.root_cause_message.include?(pattern),
      "Expected root cause containing '#{pattern}', got: #{error.root_cause_message}"
  end

  YEAR_1997 = "[Time].[1997]"

  QUARTERS = <<~MEMBERS.chomp
    [Time].[1997].[Q1]
    [Time].[1997].[Q2]
    [Time].[1997].[Q3]
    [Time].[1997].[Q4]
  MEMBERS

  MONTHS = <<~MEMBERS.chomp
    [Time].[1997].[Q1].[1]
    [Time].[1997].[Q1].[2]
    [Time].[1997].[Q1].[3]
    [Time].[1997].[Q2].[4]
    [Time].[1997].[Q2].[5]
    [Time].[1997].[Q2].[6]
    [Time].[1997].[Q3].[7]
    [Time].[1997].[Q3].[8]
    [Time].[1997].[Q3].[9]
    [Time].[1997].[Q4].[10]
    [Time].[1997].[Q4].[11]
    [Time].[1997].[Q4].[12]
  MEMBERS

  HIERARCHIZED_1997 = <<~MEMBERS.chomp
    [Time].[1997]
    [Time].[1997].[Q1]
    [Time].[1997].[Q1].[1]
    [Time].[1997].[Q1].[2]
    [Time].[1997].[Q1].[3]
    [Time].[1997].[Q2]
    [Time].[1997].[Q2].[4]
    [Time].[1997].[Q2].[5]
    [Time].[1997].[Q2].[6]
    [Time].[1997].[Q3]
    [Time].[1997].[Q3].[7]
    [Time].[1997].[Q3].[8]
    [Time].[1997].[Q3].[9]
    [Time].[1997].[Q4]
    [Time].[1997].[Q4].[10]
    [Time].[1997].[Q4].[11]
    [Time].[1997].[Q4].[12]
  MEMBERS

  describe "basic Descendants" do
    # Java: FunctionTest#testDescendantsM
    it "returns all descendants of a member" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997].[Q1])",
        <<~EXPECTED.chomp
          [Time].[1997].[Q1]
          [Time].[1997].[Q1].[1]
          [Time].[1997].[Q1].[2]
          [Time].[1997].[Q1].[3]
        EXPECTED
    end

    # Java: FunctionTest#testDescendantsDepends
    it "depends on Time hierarchy" do
      skip "TODO: assertExprDependsOn not yet available"
    end

    # Java: FunctionTest#testDescendantsML
    it "returns descendants at a given level" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Month])",
        MONTHS
    end
  end

  describe "with SELF flag" do
    # Java: FunctionTest#testDescendantsMLSelf
    it "returns descendants at level with SELF" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Quarter], SELF)",
        QUARTERS
    end

    # Java: FunctionTest#testDescendantsM2Self
    it "returns descendants at depth 2 with Self" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], 2, Self)",
        MONTHS
    end

    # Java: FunctionTest#testDescendantsMFarSelf
    it "returns empty set for descendants at very large depth with Self" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], 10000, Self)",
        ""
    end
  end

  describe "with LEAVES flag" do
    # Java: FunctionTest#testDescendantsMLLeaves
    it "returns leaves at various levels" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Year], LEAVES)",
        ""
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Quarter], LEAVES)",
        ""
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Month], LEAVES)",
        MONTHS
      assert_axis_returns @olap,
        "Descendants([Gender], [Gender].[Gender], leaves)",
        <<~EXPECTED.chomp
          [Gender].[F]
          [Gender].[M]
        EXPECTED
    end

    # Java: FunctionTest#testDescendantsMLLeavesRagged
    it "returns leaves in ragged hierarchy" do
      # no cities are at leaf level
      assert_axis_returns @olap,
        "Descendants([Store].[Israel], [Store].[Store City], leaves)",
        "",
        cube: "Sales Ragged"

      # all cities are leaves
      assert_axis_returns @olap,
        "Descendants([Geography].[Israel], [Geography].[City], leaves)",
        <<~EXPECTED.chomp,
          [Geography].[Israel].[Israel].[Haifa]
          [Geography].[Israel].[Israel].[Tel Aviv]
        EXPECTED
        cube: "Sales Ragged"

      # No state is a leaf (not even Israel, which is both a country and a
      # a state, or Vatican, with is a country/state/city)
      assert_axis_returns @olap,
        "Descendants([Geography], [Geography].[State], leaves)",
        "",
        cube: "Sales Ragged"

      # The Vatican is a nation with no children (they're all celibate,
      # you know).
      assert_axis_returns @olap,
        "Descendants([Geography], [Geography].[Country], leaves)",
        "[Geography].[Vatican]",
        cube: "Sales Ragged"
    end

    # Java: FunctionTest#testDescendantsMNLeaves
    it "returns leaves at numeric depth" do
      # leaves at depth 0 returns the member itself
      assert_axis_returns @olap,
        "Descendants([Time].[1997].[Q2].[4], 0, Leaves)",
        "[Time].[1997].[Q2].[4]"

      # leaves at depth > 0 returns the member itself
      assert_axis_returns @olap,
        "Descendants([Time].[1997].[Q2].[4], 100, Leaves)",
        "[Time].[1997].[Q2].[4]"

      # leaves at depth < 0 returns all descendants
      assert_axis_returns @olap,
        "Descendants([Time].[1997].[Q2], -1, Leaves)",
        <<~EXPECTED.chomp
          [Time].[1997].[Q2].[4]
          [Time].[1997].[Q2].[5]
          [Time].[1997].[Q2].[6]
        EXPECTED

      # leaves at depth 0 returns the member itself
      assert_axis_returns @olap,
        "Descendants([Time].[1997].[Q2], 0, Leaves)",
        <<~EXPECTED.chomp
          [Time].[1997].[Q2].[4]
          [Time].[1997].[Q2].[5]
          [Time].[1997].[Q2].[6]
        EXPECTED

      assert_axis_returns @olap,
        "Descendants([Time].[1997].[Q2], 3, Leaves)",
        <<~EXPECTED.chomp
          [Time].[1997].[Q2].[4]
          [Time].[1997].[Q2].[5]
          [Time].[1997].[Q2].[6]
        EXPECTED
    end

    # Java: FunctionTest#testDescendantsM2Leaves
    it "returns descendants at depth 2 with Leaves" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], 2, Leaves)",
        MONTHS
    end

    # Java: FunctionTest#testDescendantsMFarLeaves
    it "returns leaves at very large depth" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], 10000, Leaves)",
        MONTHS
    end

    # Java: FunctionTest#testDescendantsMEmptyLeaves
    it "returns leaves with empty depth" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], , Leaves)",
        MONTHS
    end
  end

  describe "with BEFORE flags" do
    # Java: FunctionTest#testDescendantsMLSelfBefore
    it "returns SELF_AND_BEFORE at Quarter level" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Quarter], SELF_AND_BEFORE)",
        "#{YEAR_1997}\n#{QUARTERS}"
    end

    # Java: FunctionTest#testDescendantsMLBefore
    it "returns BEFORE at Quarter level" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Quarter], BEFORE)",
        YEAR_1997
    end
  end

  describe "with AFTER flags" do
    # Java: FunctionTest#testDescendantsMLAfter
    it "returns AFTER at Quarter level" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Quarter], AFTER)",
        MONTHS
    end

    # Java: FunctionTest#testDescendantsMLAfterEnd
    it "returns empty set for AFTER at Month level" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Month], AFTER)",
        ""
    end
  end

  describe "with combined BEFORE_AND_AFTER flags" do
    # Java: FunctionTest#testDescendantsMLBeforeAfter
    it "returns BEFORE_AND_AFTER at Quarter level" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Quarter], BEFORE_AND_AFTER)",
        "#{YEAR_1997}\n#{MONTHS}"
    end

    # Java: FunctionTest#testDescendantsMLSelfBeforeAfter
    it "returns SELF_BEFORE_AFTER at Quarter level" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], [Time].[Quarter], SELF_BEFORE_AFTER)",
        HIERARCHIZED_1997
    end

    # Java: FunctionTest#testDescendantsSBA
    it "returns SELF_BEFORE_AFTER at depth 1" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], 1, SELF_BEFORE_AFTER)",
        HIERARCHIZED_1997
    end

    # Java: FunctionTest#testDescendantsMNY
    it "returns BEFORE_AND_AFTER at depth 1" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], 1, BEFORE_AND_AFTER)",
        "#{YEAR_1997}\n#{MONTHS}"
    end
  end

  describe "with numeric depth" do
    # Java: FunctionTest#testDescendantsM0
    it "returns descendants at depth 0" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], 0)",
        YEAR_1997
    end

    # Java: FunctionTest#testDescendantsM2
    it "returns descendants at depth 2" do
      assert_axis_returns @olap,
        "Descendants([Time].[1997], 2)",
        MONTHS
    end
  end

  describe "error cases" do
    # Java: FunctionTest#testDescendantsMEmptyLeavesFail
    it "fails for empty depth without LEAVES flag" do
      assert_axis_throws(
        "Descendants([Time].[1997],)",
        "No function matches signature 'Descendants(<Member>, <Empty>)")
    end

    # Java: FunctionTest#testDescendantsMEmptyLeavesFail2
    it "fails for empty depth with non-LEAVES flag" do
      assert_axis_throws(
        "Descendants([Time].[1997], , AFTER)",
        "depth must be specified unless DESC_FLAG is LEAVES")
    end
  end

  describe "second hierarchy" do
    # Java: FunctionTest#testDescendants2ndHier
    it "returns descendants from weekly hierarchy" do
      # Java expected values use SSAS-style [Time].[Weekly], but actual
      # Mondrian output uses [Time.Weekly] when SsasCompatibleNaming is false.
      assert_axis_returns @olap,
        "Descendants([Time.Weekly].[1997].[10], [Time.Weekly].[Day])",
        <<~EXPECTED.chomp
          [Time.Weekly].[1997].[10].[1]
          [Time.Weekly].[1997].[10].[23]
          [Time.Weekly].[1997].[10].[24]
          [Time.Weekly].[1997].[10].[25]
          [Time.Weekly].[1997].[10].[26]
          [Time.Weekly].[1997].[10].[27]
          [Time.Weekly].[1997].[10].[28]
        EXPECTED
    end
  end

  describe "parent-child hierarchies" do
    # Java: FunctionTest#testDescendantsParentChild
    it "returns descendants at depth 2 in parent-child hierarchy" do
      assert_axis_returns @olap,
        "Descendants([Employees], 2)",
        <<~EXPECTED.chomp,
          [Employees].[Sheri Nowmer].[Derrick Whelply]
          [Employees].[Sheri Nowmer].[Michael Spence]
          [Employees].[Sheri Nowmer].[Maya Gutierrez]
          [Employees].[Sheri Nowmer].[Roberta Damstra]
          [Employees].[Sheri Nowmer].[Rebecca Kanagaki]
          [Employees].[Sheri Nowmer].[Darren Stanz]
          [Employees].[Sheri Nowmer].[Donna Arnold]
        EXPECTED
        cube: "HR"
    end

    # Java: FunctionTest#testDescendantsParentChildBefore
    it "returns BEFORE at depth 2 in parent-child hierarchy" do
      assert_axis_returns @olap,
        "Descendants([Employees], 2, BEFORE)",
        <<~EXPECTED.chomp,
          [Employees].[All Employees]
          [Employees].[Sheri Nowmer]
        EXPECTED
        cube: "HR"
    end

    # Java: FunctionTest#testDescendantsParentChildLeaves
    it "returns leaves in parent-child hierarchy" do
      # leaves, restricted by level
      assert_axis_returns @olap,
        "Descendants([Employees].[All Employees].[Sheri Nowmer].[Michael Spence], [Employees].[Employee Id], LEAVES)",
        <<~EXPECTED.chomp,
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[John Brooks]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Todd Logan]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Joshua Several]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[James Thomas]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Robert Vessa]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Bronson Jacobs]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Rebecca Barley]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Emilio Alvaro]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Becky Waters]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[A. Joyce Jarvis]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Ruby Sue Styles]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Lisa Roy]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Ingrid Burkhardt]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Todd Whitney]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Barbara Wisnewski]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Karren Burkhardt]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[John Long]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Edwin Olenzek]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Jessie Valerio]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Robert Ahlering]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Megan Burke]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Mary Sandidge].[Karel Bates]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[James Tran]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Shelley Crow]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Anne Sims]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Clarence Tatman]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Jan Nelsen]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Jeanie Glenn]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Peggy Smith]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Tish Duff]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Anita Lucero]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Stephen Burton]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Amy Consentino]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Stacie Mcanich]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Mary Browning]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Alexandra Wellington]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Cory Bacugalupi]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Stacy Rizzi]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Mike White]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Marty Simpson]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Robert Jones]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Raul Casts]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Bridget Browqett]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Monk Skonnard].[Kay Kartz]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Jeanette Cole]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Phyllis Huntsman]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Hannah Arakawa]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Wathalee Steuber]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Pamela Cox]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Helen Lutes]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Linda Ecoffey]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Katherine Swint]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Dianne Slattengren]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Ronald Heymsfield]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Steven Whitehead]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[William Sotelo]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Beth Stanley]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Jill Markwood]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Mildred Valentine]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Suzann Reams]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Audrey Wold]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Susan French]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Trish Pederson]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Eric Renn]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Elizabeth Catalano]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Christopher Beck].[Eric Coleman]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Catherine Abel]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Emilo Miller]
          [Employees].[Sheri Nowmer].[Michael Spence].[Daniel Wolter].[Michael John Troyer].[Hazel Walker]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Sara Pettengill].[Linda Blasingame]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Sara Pettengill].[Jackie Blackwell]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Sara Pettengill].[John Ortiz]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Sara Pettengill].[Stacey Tearpak]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Sara Pettengill].[Fannye Weber]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Sara Pettengill].[Diane Kabbes]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Sara Pettengill].[Brenda Heaney]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Sara Pettengill].[Judith Karavites]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Jauna Elson]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Nancy Hirota]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Marie Moya]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Nicky Chesnut]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Karen Hall]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Greg Narberes]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Anna Townsend]
          [Employees].[Sheri Nowmer].[Michael Spence].[Dianne Collins].[Lawrence Hurkett].[Carol Ann Rockne]
        EXPECTED
        cube: "HR"

      # leaves, restricted by depth
      assert_axis_returns @olap,
        "Descendants([Employees], 1, LEAVES)",
        "",
        cube: "HR"

      assert_axis_returns @olap,
        "Descendants([Employees], 2, LEAVES)",
        <<~EXPECTED.chomp,
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Jennifer Cooper]
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Peggy Petty]
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Jessica Olguin]
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Phyllis Burchett]
          [Employees].[Sheri Nowmer].[Rebecca Kanagaki].[Juanita Sharp]
          [Employees].[Sheri Nowmer].[Rebecca Kanagaki].[Sandra Brunner]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Ernest Staton]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Rose Sims]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Lauretta De Carlo]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Mary Williams]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Terri Burke]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Audrey Osborn]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Brian Binai]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Concepcion Lozada]
          [Employees].[Sheri Nowmer].[Donna Arnold].[Howard Bechard]
          [Employees].[Sheri Nowmer].[Donna Arnold].[Doris Carter]
        EXPECTED
        cube: "HR"

      assert_axis_returns @olap,
        "Descendants([Employees], 3, LEAVES)",
        <<~EXPECTED.chomp,
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Jennifer Cooper]
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Peggy Petty]
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Jessica Olguin]
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Phyllis Burchett]
          [Employees].[Sheri Nowmer].[Rebecca Kanagaki].[Juanita Sharp]
          [Employees].[Sheri Nowmer].[Rebecca Kanagaki].[Sandra Brunner]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Ernest Staton]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Rose Sims]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Lauretta De Carlo]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Mary Williams]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Terri Burke]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Audrey Osborn]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Brian Binai]
          [Employees].[Sheri Nowmer].[Darren Stanz].[Concepcion Lozada]
          [Employees].[Sheri Nowmer].[Donna Arnold].[Howard Bechard]
          [Employees].[Sheri Nowmer].[Donna Arnold].[Doris Carter]
        EXPECTED
        cube: "HR"

      # note that depth is RELATIVE to the starting member
      assert_axis_returns @olap,
        "Descendants([Employees].[Sheri Nowmer].[Roberta Damstra], 1, LEAVES)",
        <<~EXPECTED.chomp,
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Jennifer Cooper]
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Peggy Petty]
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Jessica Olguin]
          [Employees].[Sheri Nowmer].[Roberta Damstra].[Phyllis Burchett]
        EXPECTED
        cube: "HR"

      # Howard Bechard is a leaf member -- appears even at depth 0
      assert_axis_returns @olap,
        "Descendants([Employees].[All Employees].[Sheri Nowmer].[Donna Arnold].[Howard Bechard], 0, LEAVES)",
        "[Employees].[Sheri Nowmer].[Donna Arnold].[Howard Bechard]",
        cube: "HR"

      assert_axis_returns @olap,
        "Descendants([Employees].[All Employees].[Sheri Nowmer].[Donna Arnold].[Howard Bechard], 1, LEAVES)",
        "[Employees].[Sheri Nowmer].[Donna Arnold].[Howard Bechard]",
        cube: "HR"

      assert_expression_returns @olap,
        "Count(Descendants([Employees], 2, LEAVES))", "16",
        cube: "HR"

      assert_expression_returns @olap,
        "Count(Descendants([Employees], 3, LEAVES))", "16",
        cube: "HR"

      assert_expression_returns @olap,
        "Count(Descendants([Employees], 4, LEAVES))", "63",
        cube: "HR"

      assert_expression_returns @olap,
        "Count(Descendants([Employees], 999, LEAVES))", "1,044",
        cube: "HR"

      # Negative depth acts like +infinity (per MSAS).  Run the test several
      # times because we had a non-deterministic bug here.
      100.times do
        assert_expression_returns @olap,
          "Count(Descendants([Employees], -1, LEAVES))", "1,044",
          cube: "HR"
      end
    end
  end

  describe "set argument" do
    # Java: FunctionTest#testDescendantsSet
    it "returns descendants from a set of members" do
      assert_axis_returns @olap,
        "Descendants({[Time].[1997].[Q4], [Time].[1997].[Q2]}, 1)",
        <<~EXPECTED.chomp
          [Time].[1997].[Q4].[10]
          [Time].[1997].[Q4].[11]
          [Time].[1997].[Q4].[12]
          [Time].[1997].[Q2].[4]
          [Time].[1997].[Q2].[5]
          [Time].[1997].[Q2].[6]
        EXPECTED

      assert_axis_returns @olap,
        "Descendants({[Time].[1997]}, [Time].[Month], LEAVES)",
        MONTHS
    end

    # Java: FunctionTest#testDescendantsSetEmpty
    it "handles empty set argument" do
      assert_axis_throws(
        "Descendants({}, 1)",
        "Cannot deduce type of set")

      assert_axis_returns @olap,
        "Descendants(Filter({[Time].[Time].Members}, 1=0), 1)",
        ""
    end
  end
end
