#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import logging
import os
import sys
import unittest

my_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(my_dir))

import topology_match_policy
from topology_match_policy import _check_allocation as check_allocation

topology_match_policy.DATA_PATH = os.path.join(my_dir, "project_resource_allocations.json")
topology_match_policy._log.setLevel(logging.WARNING)

SCHEDD = "submittest0000.chtc.wisc.edu"
SCHEDD2 = "xd-submit.chtc.wisc.edu"
EXEC_RES = "CHTC-ITB-SLURM-CE"
EXEC_RES2 = "TACC-Stampede2"

class TestTopologyMatchPolicy(unittest.TestCase):
    def test_CHTC_Staff(self):
        assert check_allocation("CHTC-Staff", SCHEDD, EXEC_RES) == "OK"

    def test_TG_CHE200122(self):
        assert check_allocation("TG-CHE200122", SCHEDD2, EXEC_RES2) == "OK"

    def test_UTAustin_Zimmerman(self):
        assert check_allocation("UTAustin_Zimmerman", SCHEDD2, EXEC_RES2) == "OK"

    def test_project_not_found(self):
        assert check_allocation("fdsfsdfwef", "", "") == "project not found"

    def test_no_ResourceAllocations(self):
        assert check_allocation("no_ResourceAllocations", "", "") == "no ResourceAllocations"

    def test_no_SubmitResources(self):
        assert check_allocation("no_SubmitResources1", SCHEDD, EXEC_RES) == "no matches"
        # ^^ no_SubmitResources1 should also print a warning about having malformed project data
        assert check_allocation("no_SubmitResources2", SCHEDD, EXEC_RES) == "no matches"

    def test_no_matching_SubmitResources(self):
        assert check_allocation("no_matching_SubmitResources", SCHEDD, EXEC_RES) == "no matches"

    def test_no_ExecuteResourceGroups(self):
        assert check_allocation("no_ExecuteResourceGroups1", SCHEDD, EXEC_RES) == "no matches"
        # ^^ no_ExecuteResourceGroups1 should also print a warning about having malformed project data
        assert check_allocation("no_ExecuteResourceGroups2", SCHEDD, EXEC_RES) == "no matches"

    def test_no_matching_ExecuteResourceGroups(self):
        assert check_allocation("no_matching_ExecuteResourceGroups", SCHEDD, EXEC_RES) == "no matches"

if __name__ == "__main__":
    unittest.main()
