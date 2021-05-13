# inspired by https://github.com/jamesletts/CMSglideinWMSValidation/blob/master/CMSGroupMapper.py
"""Contains code to match job resource allocations based on Topology data
Topology projects data is downloaded and cached.

- is_project_using_xrac_allocation checks a project name (e.g. from the job's ProjectName attribute)
    against the schedd it's been submitted from and the Topology resource group that the XSEDE resource is in.

"""
from __future__ import print_function

import logging
import re
import sys
import time
import xml.etree.ElementTree as ET


if sys.version_info[0] >= 3:
    from urllib.request import urlopen  # Python 3
else:
    from urllib2 import urlopen  # Python 2

try:
    from typing import Optional, Union  # Python 3 or Python 2 + typing module
except ImportError:
    pass  # only used for linting


#
#
# Public
#
#

TOPOLOGY = "https://topology.opensciencegrid.org"
PROJECTS_URL = TOPOLOGY + "/miscproject/xml"
PROJECTS_CACHE_LIFETIME = 60.0


def is_project_using_resource_allocation(project_name, schedd, resource_group):  # type: (str, str, str) -> bool
    """Does various checks to make sure the project named by project_name
    is allowed to submit from the given schedd to the given resource group,
    downloading the projects data from Topology if necessary.

    `project_name` should be a Topology Project name.
    `schedd` should be a Topology Resource name.
    `resource_group` should be a Topology ResourceGroup name.

    Returns True if the project is allowed.

    """
    # This function needs to return a bool so we put the actual checks into a
    # separate function that can return an error reason so we can test it.
    projects_tree = _get_projects()
    return _check_allocation(projects_tree, project_name, schedd, resource_group) == "OK"


#
#
# Internal
#
#

log = logging.getLogger(__name__)


# took this code from Topology
class _CachedData(object):
    def __init__(self, data=None, timestamp=0, force_update=True, cache_lifetime=60*15,
                 retry_delay=60):
        self.data = data
        self.timestamp = timestamp
        self.force_update = force_update
        self.cache_lifetime = cache_lifetime
        self.retry_delay = retry_delay
        self.next_update = self.timestamp + self.cache_lifetime

    def should_update(self):
        return self.force_update or not self.data or time.time() > self.next_update

    def try_again(self):
        self.next_update = time.time() + self.retry_delay

    def update(self, data):
        self.data = data
        self.timestamp = time.time()
        self.next_update = self.timestamp + self.cache_lifetime
        self.force_update = False


_projects_cache = _CachedData(cache_lifetime=PROJECTS_CACHE_LIFETIME, retry_delay=30.0)


def _safe_element_text(element):  # type: (Optional[ET.Element]) -> str
    return getattr(element, "text", "").strip()


def _get_projects():  # type: () -> Optional[ET.Element]
    global _projects_cache

    if not _projects_cache.should_update():
        log.debug("Cache lifetime / retry delay not expired, returning cached data (if any)")
        return _projects_cache.data

    try:
        # Python 2 does not have a context manager for urlopen
        response = urlopen(PROJECTS_URL)
        try:
            xml_text = response.read()  # type: Union[bytes, str]
        finally:
            response.close()
    except (EnvironmentError) as err:
        log.warning("Topology projects query failed: %s", err)
        _projects_cache.try_again()
        if _projects_cache.data:
            log.debug("Returning cached data")
            return _projects_cache.data
        else:
            log.error("Failed to update and no cached data")
            return None

    if not xml_text:
        log.warning("Topology projects query returned no data")
        _projects_cache.try_again()
        if _projects_cache.data:
            log.debug("Returning cached data")
            return _projects_cache.data
        else:
            log.error("Failed to update and no cached data")
            return None

    try:
        element = ET.fromstring(xml_text)  # fromstring accepts both bytes and str
    except (ET.ParseError, UnicodeDecodeError) as err:
        log.warning("Topology projects query couldn't be parsed: %s", err)
        _projects_cache.try_again()
        if _projects_cache.data:
            log.debug("Returning cached data")
            return _projects_cache.data
        else:
            log.error("Failed to update and no cached data")
            return None

    log.debug("Caching and returning new data")
    _projects_cache.update(element)
    return _projects_cache.data


def _check_allocation(projects_tree, project_name, schedd, resource_group):  # type: (Optional[ET.Element], str, str, str) -> str
    """Does various checks to make sure the project named by project_name
    is allowed to submit from the given schedd to the given resource group,
    using the ElementTree projects_tree for the data.

    Returns "OK" if yes, otherwise the reason for why not.

    """
    if re.search(r"[\t\r\n']", project_name):
        log.error("Invalid character in project name %s", project_name)
        return "bad project_name"

    if projects_tree is None or len(projects_tree) < 1:
        # _get_projects() has already warned us
        return "no Projects"

    project_element = projects_tree.find("./Project/[Name='%s']" % project_name)
    if project_element is None or len(project_element) < 1:
        log.warning("Project with name %s not found", project_name)
        return "no Name"

    resource_allocation_elements = project_element.findall("./ResourceAllocations/ResourceAllocation")
    if not resource_allocation_elements:
        log.info("Project %s has no ResourceAllocations", project_name)
        return "no ResourceAllocations"

    for idx, ra in enumerate(resource_allocation_elements):
        txt_prefix = "Project %s ResourceAllocation %d" % (project_name, idx)
        submit_resource_elements = ra.findall("./SubmitResources/SubmitResource")
        if not submit_resource_elements:
            log.debug("%s has no SubmitResources", txt_prefix)
            continue
        execute_resource_group_elements = ra.findall("./ExecuteResourceGroups/ExecuteResourceGroup")
        if not execute_resource_group_elements:
            log.debug("%s has no ExecuteResourceGroups", txt_prefix)
            continue

        submit_resources = {_safe_element_text(x) for x in submit_resource_elements}
        if schedd not in submit_resources:
            log.debug("%s does not allow SubmitResource %s", txt_prefix, schedd)
            continue
        execute_resource_groups = {_safe_element_text(x.find("./GroupName")) for x in execute_resource_group_elements}
        if resource_group not in execute_resource_groups:
            log.debug("%s does not contain RG %s", txt_prefix, schedd)
            continue

        return "OK"

    log.info("Project %s found no matches for schedd %s and resource_group %s", project_name, schedd, resource_group)
    return "no matches"

#
#
# Testing
#
#

__MOCK_PROJECT_XML = r"""
<Projects>
    <Project/> <!-- bad project, no name -->

    <Project>
        <Name>No_Alloc</Name>
    </Project>

    <Project>
        <Name>Empty_RAs</Name>
        <ResourceAllocations/>
    </Project>

    <Project>
        <Name>No_Schedds</Name>
        <ResourceAllocations>
            <ResourceAllocation>
                <Type>XRAC</Type>
                <SubmitResources/>
                <ExecuteResourceGroups>
                    <ExecuteResourceGroup>
                        <GroupName>MyRG</GroupName>
                        <LocalAllocationID>myalloc</LocalAllocationID>
                    </ExecuteResourceGroup>
                </ExecuteResourceGroups>
            </ResourceAllocation>
        </ResourceAllocations>
    </Project>

    <Project>
        <Name>No_RGs</Name>
        <ResourceAllocations>
            <ResourceAllocation>
                <Type>XRAC</Type>
                <SubmitResources>
                    <SubmitResource>SUBMIT-1</SubmitResource>
                </SubmitResources>
                <ExecuteResourceGroups/>
            </ResourceAllocation>
        </ResourceAllocations>
    </Project>

    <Project>
        <Name>Malformed_RG</Name>
        <ResourceAllocations>
            <ResourceAllocation>
                <Type>XRAC</Type>
                <SubmitResources>
                    <SubmitResource>SUBMIT-1</SubmitResource>
                </SubmitResources>
                <ExecuteResourceGroups>
                    <ExecuteResourceGroup>
                        MyRG
                    </ExecuteResourceGroup>
                </ExecuteResourceGroups>
            </ResourceAllocation>
        </ResourceAllocations>
    </Project>

    <Project>
        <Name>OK</Name>
        <ResourceAllocations>
            <ResourceAllocation>
                <Type>XRAC</Type>
                <SubmitResources>
                    <SubmitResource>SUBMIT-1</SubmitResource>
                </SubmitResources>
                <ExecuteResourceGroups>
                    <ExecuteResourceGroup>
                        <GroupName>MyRG</GroupName>
                        <LocalAllocationID>myalloc</LocalAllocationID>
                    </ExecuteResourceGroup>
                </ExecuteResourceGroups>
            </ResourceAllocation>
        </ResourceAllocations>
    </Project>

    <Project>
        <Name>OK2</Name>
        <ResourceAllocations>
            <ResourceAllocation>
                <Type>XRAC</Type>
                <SubmitResources>
                    <SubmitResource>SUBMIT-1</SubmitResource>
                </SubmitResources>
                <ExecuteResourceGroups>
                    <ExecuteResourceGroup>
                        <GroupName>MyRG</GroupName>
                        <LocalAllocationID>myalloc</LocalAllocationID>
                    </ExecuteResourceGroup>
                </ExecuteResourceGroups>
            </ResourceAllocation>

            <ResourceAllocation>
                <Type>XRAC</Type>
                <SubmitResources>
                    <SubmitResource>SUBMIT-2</SubmitResource>
                </SubmitResources>
                <ExecuteResourceGroups>
                    <ExecuteResourceGroup>
                        <GroupName>MyRG2</GroupName>
                        <LocalAllocationID>myalloc2</LocalAllocationID>
                    </ExecuteResourceGroup>
                </ExecuteResourceGroups>
            </ResourceAllocation>
        </ResourceAllocations>
    </Project>
</Projects>
"""

# fmt:off
__TEST_PARAMS = [
    ["Bad'Name",     "SUBMIT-1", "MyRG",   "bad project_name"],
    ["Missing",      "SUBMIT-1", "MyRG",   "no Name"],
    ["No_Alloc",     "SUBMIT-1", "MyRG",   "no ResourceAllocations"],
    ["Empty_RAs",    "SUBMIT-1", "MyRG",   "no ResourceAllocations"],
    ["No_Schedds",   "SUBMIT-1", "MyRG",   "no matches"],
    ["No_RGs",       "SUBMIT-1", "MyRG",   "no matches"],
    ["Malformed_RG", "SUBMIT-1", "MyRG",   "no matches"],
    ["OK",           "SMIT-1",   "MyRG",   "no matches"],
    ["OK",           "SUBMIT-1", "YourRG", "no matches"],
    ["OK",           "SUBMIT-1", "MyRG",   "OK"],
    ["OK2",          "SUBMIT-2", "MyRG2",  "OK"],
    ["OK2",          "SUBMIT-1", "MyRG2",  "no matches"],
]
# fmt:on

if __name__ == "__main__":
    # self-test
    logging.basicConfig(level=logging.DEBUG)
    projects_tree = ET.fromstring(__MOCK_PROJECT_XML)

    for project_name, schedd, resource_group, expected in __TEST_PARAMS:
        result = _check_allocation(projects_tree, project_name, schedd, resource_group)
        assert result == expected, \
            "expected %r, got %r for params %r, %r, %r" % (expected, result, project_name, schedd, resource_group)

    print("All OK")
