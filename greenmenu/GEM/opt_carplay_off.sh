#!/bin/sh
# Green menu switch (scripts/menu_switch.sh).
. "`dirname "$0"`/common.sh"
sh "$PKG/scripts/menu_switch.sh" CLUSTERMAP_CARPLAY_MAP 0 now "CarPlay map on the cluster: OFF. The cluster keeps the car's own map; CarPlay itself is not affected"
exit 0
