"""Схема событий аналитики roguelike-game.

Держит SUPPORTED_SCHEMA_VERSION, registry event'ов и правила validation.
Источник правды — autoloads/analytics.gd + docs/engineering/analytics.md
из основной кодовой базы Godot. Разъезжание — регрессия PR 3.
"""

from __future__ import annotations

from dataclasses import dataclass

SUPPORTED_SCHEMA_VERSION: int = 1

ENVELOPE_REQUIRED: tuple[str, ...] = (
    "schema_version",
    "event_name",
    "event_id",
    "timestamp_ms",
    "installation_id",
    "session_id",
    "game_version",
    "build_commit",
    "balance_version",
    "platform",
    "locale",
    "payload",
)

RUN_SCOPED_EVENTS: frozenset[str] = frozenset({
    "run_started",
    "run_finished",
    "floor_started",
    "floor_completed",
    "floor_weapon_summary",
    "floor_enemy_summary",
    "floor_economy_summary",
    "weapon_equipped",
    "upgrade_offer_shown",
    "upgrade_selected",
    "potion_used",
    "room_first_entered",
})

FLOOR_SCOPED_EVENTS: frozenset[str] = frozenset({
    "floor_started",
    "floor_completed",
    "floor_weapon_summary",
    "floor_enemy_summary",
    "floor_economy_summary",
    "room_first_entered",
})

SESSION_END_REASONS: frozenset[str] = frozenset({
    "normal_exit",
    "quit_to_menu",
    "restart",
    "application_closed",
    "unknown",
})

RUN_END_REASONS: frozenset[str] = frozenset({
    "player_death",
    "victory",
    "quit_to_menu",
    "restart",
    "application_closed",
    "unknown",
})

WEAPON_EQUIP_SOURCES: frozenset[str] = frozenset({
    "starting",
    "chest",
    "pickup",
    "debug",
    "other",
})


@dataclass(frozen=True)
class EventSpec:
    name: str
    required_payload: tuple[str, ...] = ()
    numeric_payload: tuple[str, ...] = ()
    """Поля payload, которые должны конвертироваться в число ≥ 0."""


EVENT_SPECS: dict[str, EventSpec] = {
    "session_started": EventSpec(
        name="session_started",
        required_payload=("debug_build",),
    ),
    "session_finished": EventSpec(
        name="session_finished",
        required_payload=("reason",),
    ),
    "run_started": EventSpec(
        name="run_started",
        required_payload=("starting_weapon_id", "starting_max_health", "starting_level"),
        numeric_payload=("starting_max_health", "starting_level"),
    ),
    "run_finished": EventSpec(
        name="run_finished",
        required_payload=(
            "reason",
            "duration_seconds",
            "floor_reached",
            "player_level",
            "gold_earned",
            "enemies_killed",
            "damage_taken",
            "damage_dealt",
        ),
        numeric_payload=(
            "duration_seconds",
            "floor_reached",
            "player_level",
            "gold_earned",
            "enemies_killed",
            "damage_taken",
            "damage_dealt",
            "potions_remaining",
        ),
    ),
    "floor_started": EventSpec(
        name="floor_started",
        required_payload=("layout_archetype", "zone"),
    ),
    "floor_completed": EventSpec(
        name="floor_completed",
        required_payload=(
            "duration_seconds",
            "kills",
            "gold_earned",
            "damage_taken",
            "damage_dealt",
            "rooms_visited",
        ),
        numeric_payload=(
            "duration_seconds",
            "kills",
            "gold_earned",
            "damage_taken",
            "damage_dealt",
            "rooms_visited",
        ),
    ),
    "floor_weapon_summary": EventSpec(
        name="floor_weapon_summary",
        required_payload=("weapon_id", "equipped_seconds", "attacks", "damage_dealt"),
        numeric_payload=(
            "equipped_seconds",
            "combat_seconds",
            "attacks",
            "projectiles_fired",
            "attacks_with_hit",
            "projectiles_hit",
            "targets_hit",
            "damage_dealt",
            "kills",
            "damage_taken_while_equipped",
        ),
    ),
    "floor_enemy_summary": EventSpec(
        name="floor_enemy_summary",
        required_payload=("enemy_id", "temperament", "elite_rank"),
        numeric_payload=(
            "elite_rank",
            "spawned",
            "killed",
            "damage_to_player",
            "hits_to_player",
            "damage_received",
            "time_alive_seconds",
            "player_deaths",
        ),
    ),
    "floor_economy_summary": EventSpec(
        name="floor_economy_summary",
        numeric_payload=(
            "gold_from_enemies",
            "gold_from_chests",
            "gold_from_props",
            "gold_from_bosses",
            "potions_received",
            "potions_used",
            "healing_received",
            "overheal",
            "chests_opened",
            "weapons_offered",
            "weapons_picked",
        ),
    ),
    "weapon_equipped": EventSpec(
        name="weapon_equipped",
        required_payload=("weapon_id", "source"),
    ),
    "upgrade_offer_shown": EventSpec(
        name="upgrade_offer_shown",
        required_payload=("choice_level", "current_weapon_id", "offered_ids"),
        numeric_payload=("choice_level", "player_health", "player_max_health"),
    ),
    "upgrade_selected": EventSpec(
        name="upgrade_selected",
        required_payload=("selected_id", "offer_position", "stack_before", "stack_after"),
        numeric_payload=(
            "offer_position",
            "stack_before",
            "stack_after",
            "choice_time_seconds",
        ),
    ),
    "potion_used": EventSpec(
        name="potion_used",
        required_payload=("health_before", "max_health", "heal_amount", "actual_healed", "overheal"),
        numeric_payload=("health_before", "max_health", "heal_amount", "actual_healed", "overheal"),
    ),
    "room_first_entered": EventSpec(
        name="room_first_entered",
        required_payload=("room_id", "role"),
        numeric_payload=("seconds_since_floor_start", "player_health", "alive_enemies"),
    ),
}


def event_spec_or_none(event_name: str) -> EventSpec | None:
    return EVENT_SPECS.get(event_name)


def is_known_event(event_name: str) -> bool:
    return event_name in EVENT_SPECS
