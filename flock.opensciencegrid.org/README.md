## Group limits in the log file and FE config

(tested on a 3.9.2 frontend)

-   Here's the log file entry for "Group glideins found" along with an explanation of where the various numbers come from:

>   Group glideins found total #A limit #B curb #C; of these idle #I limit #J curb #K running #L

This is assuming a partitionable-slot environment.

-   #A (glideins total): partitionable+dynamic slots
-   #B (glideins limit): "max" from "running_glideins_total" in the FE group config
-   #C (glideins curb):  "curb" from "running_glideins_total" in the FE group config
-   #I (idle):  'idle' p-slots
-   #J (limit): "max" from "idle_vms_total" in the FE group config
-   #K (curb):  "curb" from "idle_vms_total" in the FE group config
-   #L (running): d-slots

A p-slot is considered 'idle' if:
    -   it has no d-slots OR
    -   it doesn't have free at least 1 CPU, 2500 MB RAM and, if there are GPUs, 1 GPU
