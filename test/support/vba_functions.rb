# frozen_string_literal: true

# The Vba and the Excel function tests call the Java classes directly, and both
# need the same class names and the same tolerance. The Java classes each hold a
# private SMALL field, and one definition serves both tests here.

Excel = Java::MondrianOlapFunVba::Excel
Vba = Java::MondrianOlapFunVba::Vba
VBA_TOLERANCE = 1e-10
