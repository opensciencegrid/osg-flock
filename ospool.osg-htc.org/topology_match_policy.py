########################################
# A frontend match policy
# (see https://glideinwms.fnal.gov/doc.prd/frontend/configuration.html#match_example)
# Verifies, based on topology data, that the job is part of a project that is
# allowed to submit to the given resource, from the submit node it came in on.
# Topology data must already exist in
# "/run/topology-cache/project_resource_allocations.json"
# which is created by the topology-cacher cron job.
#
# This takes the place of ProjectName checks in the job query_expr for groups
# made for allocation-based submission.
########################################

import json
import logging
import logging.handlers
import time
import pprint


DATA_PATH = "/run/topology-cache/project_resource_allocations.json"
LOGLEVEL = logging.INFO
LOGFILE = "/var/log/gwms-frontend/topology-match-policy.log"

_log = logging.getLogger(__name__)
_log.setLevel(LOGLEVEL)
_formatter = logging.Formatter("[%(asctime)s] %(levelname)s: %(name)s: %(message)s")
try:
    _fh = logging.handlers.RotatingFileHandler(
        LOGFILE, maxBytes=10485760, backupCount=1
    )
    _fh.setLevel(LOGLEVEL)
    _fh.setFormatter(_formatter)
    _log.addHandler(_fh)
except EnvironmentError as err:
    _sh = logging.StreamHandler()
    _sh.setLevel(LOGLEVEL)
    _sh.setFormatter(_formatter)
    _log.addHandler(_sh)
    _log.warning("Couldn't open log file %s: %s; logging to console instead", LOGFILE, err)


def match(job, glidein):
    try:
        attrs = glidein.get("attrs", {})

        project_name = job.get("ProjectName", "")
        global_job_id = job.get("GlobalJobID", "")
        execute_resource_name = attrs.get("GLIDEIN_ResourceName", "")
        schedd_fqdn = job.get("GlobalJobID", "").split("#")[0]

        if not (project_name and schedd_fqdn and execute_resource_name):
            return False

        _log.debug("checking ProjectName:%s, GlobalJobID:%s, GLIDEIN_ResourceName:%s", project_name, global_job_id, execute_resource_name)

        return (
            _check_allocation(
                project_name=project_name,
                schedd_fqdn=schedd_fqdn,
                execute_resource_name=execute_resource_name,
            )
            == "OK"
        )
    except Exception:
        _log.exception("Exception happened when evaluating Topology match.")
        return False


factory_query_expr = "True"
job_query_expr = "True"
factory_match_attrs = {
    "GLIDEIN_ResourceName": {
        "type": "string",
        "comment": "ResourceName used in topology policy",
    },
}
job_match_attrs = {
    "ProjectName": {
        "type": "string",
        "comment": "Job ProjectName used in topology policy",
    },
    "GlobalJobID": {
        "type": "string",
        "comment": "GlobalJobID which contains the schedd fqdn used in topology policy",
    },
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
        txt_prefix = "Project %s ResourceAllocation #%d" % (project_name, idx + 1)
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
