import json
import logging
import time
import pprint


DATA_PATH = "/run/topology-cache/project_resource_allocations.json"

_log = logging.getLogger(__name__)


########################################
# policy.py (see https://glideinwms.fnal.gov/doc.prd/frontend/configuration.html#match_example)
def match(job, glidein):
    try:
        _log.warning("match was called with\n%s\n%s", pprint.pformat(job), pprint.pformat(glidein))
        with open("/tmp/topology_match_log", "a+") as fh:
            fh.write("%s - match was called with:\n%s\n%s\n" % (time.ctime(), pprint.pformat(job), pprint.pformat(glidein)))

        project_name = job.get("ProjectName", "")
        schedd_fqdn = job.get("GlobalJobID", "").split("#")[0]
        execute_resource_name = glidein.get("attrs", {}).get("GLIDEIN_ResourceName", "")

        if not (project_name and schedd_fqdn and execute_resource_name):
            return False

        return (
            _check_allocation(
                project_name=project_name,
                schedd_fqdn=schedd_fqdn,
                execute_resource_name=execute_resource_name,
            )
            == "OK"
        )
    except Exception:
        _log.exception("exception happened")
        return False

factory_query_expr = "True"
job_query_expr = "True"
factory_match_attrs = {
    "GLIDEIN_ResourceName": {"type": "string", "comment": "ResourceName used in topology policy"},
}
job_match_attrs = {
    "ProjectName": {"type": "string", "comment": "Job Project ID used in topology policy"},
    "GlobalJobID": {"type": "string", "comment": "Global Job ID which contains the schedd fqdn"},
}
########################################


#
# internal
#

class CachedData:
    def __init__(
        self,
        updater=lambda: None,
        initial_data=None,
        timestamp=0.0,
        force_update=True,
        cache_lifetime=60.0 * 5,
        retry_delay=60.0,
    ):
        self.data = initial_data
        self.timestamp = timestamp
        self.force_update = force_update
        self.cache_lifetime = cache_lifetime
        self.retry_delay = retry_delay
        self.next_update = self.timestamp + self.cache_lifetime
        self.updater = updater

    def should_update(self):
        return self.force_update or not self.data or time.time() > self.next_update

    def get_data(self):
        if self.should_update():
            self.force_update = False
            new_data = self.updater()
            if new_data is not None:
                self.data = new_data
                self.timestamp = time.time()
                self.next_update = self.timestamp + self.cache_lifetime
            else:
                self.next_update = time.time() + self.retry_delay
        return self.data


def load_data_file():
    try:
        with open(DATA_PATH) as fp:
            new_data = json.load(fp)
        return new_data
    except (OSError, json.JSONDecodeError) as err:
        _log.warning("Couldn't load data: %r", err)
        return None


_project_allocations_data = CachedData(updater=load_data_file)



def _check_allocation(project_name, schedd_fqdn, execute_resource_name):
    allocations_by_project = _project_allocations_data.get_data()
    if allocations_by_project is None:
        return "couldn't load data"
    if project_name not in allocations_by_project:
        _log.info("Project %s not found", project_name)
        return "project not found"
    allocations = allocations_by_project[project_name]

    if not allocations:
        _log.debug("Projects %s has no allocations", project_name)
        return "no ResourceAllocations"

    for idx, allocation in enumerate(allocations):
        txt_prefix = "Project %s ResourceAllocation %d" % (project_name, idx)
        try:

            # Check the schedd's FQDN against the allowed SubmitResources

            submit_resources = allocation["submit_resources"]
            if not submit_resources:
                _log.debug("%s has no SubmitResources", txt_prefix)
                continue
            if schedd_fqdn not in [sr["fqdn"] for sr in submit_resources]:
                _log.debug(
                    "%s does not allow SubmitResource with FQDN %s",
                    txt_prefix,
                    schedd_fqdn,
                )
                continue

            # Check the factory entry GLIDEIN_ResourceName against the allowed ExecuteResourceGroups

            execute_resource_groups = allocation["execute_resource_groups"]
            if not execute_resource_groups:
                _log.debug("%s has no ExecuteResourceGroups", txt_prefix)
                continue

            found = False
            for erg in execute_resource_groups:
                for ce in erg["ces"]:
                    if execute_resource_name == ce["name"]:
                        found = True
                        break
                if found:
                    break
            if not found:
                _log.debug(
                    "%s does not contain Resource %s", txt_prefix, execute_resource_name
                )
                continue

        except (KeyError, TypeError, ValueError) as err:
            _log.warning("%s has malformed project data: %r", txt_prefix, err)
            continue

        _log.info(
            "Project %s matched for schedd %s and Resource %s",
            project_name,
            schedd_fqdn,
            execute_resource_name,
        )
        return "OK"

    _log.info(
        "Project %s found no matches for schedd %s and Resource %s",
        project_name,
        schedd_fqdn,
        execute_resource_name,
    )
    return "no matches"



# TODO Add tests
# run the mock XML through the topology_cacher
