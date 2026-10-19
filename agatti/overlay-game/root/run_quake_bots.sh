#!/bin/sh
# Deathmatch against bots on top of run_quake.sh.
#   ./run_quake_bots.sh [map] [bots] [skill]
#   map    oa_dm1 (default); others: oa_dm2 .. oa_dm7, oa_rpg3dm2, ...
#   bots   number of bots, 3 by default
#   skill  1 (easy) .. 5 (nightmare), 3 by default
# Further engine arguments can follow, e.g. ./run_quake_bots.sh oa_dm2 5 4 +set fraglimit 30

MAP=${1:-oa_dm1}
BOTS=${2:-3}
SKILL=${3:-3}
[ $# -gt 0 ] && shift
[ $# -gt 0 ] && shift
[ $# -gt 0 ] && shift

# bot_minplayers fills the game with bots up to that many players
# (the local player counts), so no bot names are needed.
exec "$(dirname "$0")/run_quake.sh" \
	+set g_gametype 0 \
	+set bot_enable 1 \
	+set bot_minplayers $((BOTS + 1)) \
	+set g_spSkill "$SKILL" \
	+set fraglimit 20 \
	+set timelimit 10 \
	+map "$MAP" \
	"$@"
