# match_rules.gd — constants defining a match: zone phases, team sizes,
# scoring (placement), plus match-level tunables. Server-authoritative.
class_name MatchRules
extends RefCounted


enum { SOLO, DUO, SQUAD }

const MODE_NAMES := { SOLO: "solo", DUO: "duo", SQUAD: "squad" }
const MODE_BY_NAME := { "solo": SOLO, "duo": DUO, "squad": SQUAD }
const MODE_PLAYERS := { SOLO: 8, DUO: 8, SQUAD: 9 }   # small by design; scale after perf tests (see PRD §5)
const MODE_TEAM_SIZE := { SOLO: 1, DUO: 2, SQUAD: 3 }


static func mode_id(name: String) -> int:
	return MODE_BY_NAME.get(String(name).to_lower(), SOLO)


static func mode_name(id: int) -> String:
	return MODE_NAMES.get(id, "solo")


# --- safe zone: island starts ~480 m radius; final ring leaves a small pit.
# phases: wait_s -> shrink_s -> hold; dps applied to players outside cur ring.
const ZONE_PHASES := [
	{"wait_s": 40.0, "shrink_s": 34.0, "dps": 2.0, "r_mult": 0.62},
	{"wait_s": 26.0, "shrink_s": 26.0, "dps": 4.0, "r_mult": 0.66},
	{"wait_s": 20.0, "shrink_s": 22.0, "dps": 7.0, "r_mult": 0.64},
	{"wait_s": 15.0, "shrink_s": 18.0, "dps": 11.0, "r_mult": 0.60},
	{"wait_s": 12.0, "shrink_s": 14.0, "dps": 16.0, "r_mult": 0.42},
	{"wait_s": 10.0, "shrink_s": 12.0, "dps": 22.0, "r_mult": 0.30},
	{"wait_s": 8.0, "shrink_s": 10.0, "dps": 30.0, "r_mult": 0.35},
	{"wait_s": 6.0, "shrink_s": 8.0, "dps": 40.0, "r_mult": 0.12},
]


# Movement caps (server clamps with these; sanity-rate-limits inputs).
const SPEED_WALK := 4.4
const SPEED_SPRINT := 6.6
const SPEED_CROUCH := 2.2
const SPEED_AIRBORNE_PLANE := 30.0
const SPEED_CHUTE_FALL := 11.0
const SPEED_CHUTE_DRIFT := 10.0

const PLANE_ALT := 130.0
const DEPLOY_ALT_MAX := 118.0
const DEPLOY_ALT_MIN := 55.0


static func team_count(mode: int) -> int:
	return int(MODE_PLAYERS[mode]) / int(MODE_TEAM_SIZE[mode])


# Placement: eliminated earlier = numerically higher placement number.
# Winner team members share placement 1.
static func placements(mode: int, teams_by_rank: Array, pid_team: Dictionary) -> Dictionary:
	var res := {}
	var team_rank := 1
	for team in teams_by_rank:
		for pid in pid_team:
			if pid_team[pid] == team:
				res[pid] = team_rank
		team_rank += 1
	return res
