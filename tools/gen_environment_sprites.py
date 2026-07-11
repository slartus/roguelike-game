#!/usr/bin/env python3
"""
Генератор pixel-art tile'ов подземелья: пол, стены, wall caps, doorway.

Каждый tile 20×20 (совпадает с TILE_SIZE в floor.gd). Godot тайлит их
через Polygon2D.texture + texture_repeat=ENABLED.

Плюс к базовым floor.png / wall.png — набор материалов по зонам башни:
- 10 floor материалов (wood_floor, dark_wood_floor, corridor_stone,
  light_stone_tile, reinforced_stone, stone_metal_grid,
  heat_stained_stone, damaged_tower_stone, wet_basement_stone,
  cave_ground);
- 6 wall материалов (plaster_wall, wood_panel_wall, tower_stone_wall,
  technical_stone_wall, basement_brick_wall, natural_cave_wall);
- wall_cap для каждого wall материала — визуально отличается от face
  (светлее сверху, "козырёк");
- doorway_threshold — общая metallic полоса-порог.

Материал = палитра + строчный ASCII-паттерн. Генератор рендерит по одной
20×20 картинке на каждый материал. Wall cap делается автоматически:
берётся тот же паттерн, но верхняя половина осветляется.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "environment"

TILE = 20


def render(rows: list[str], palette: dict[str, tuple[int, int, int, int]]) -> Image.Image:
	height = len(rows)
	width = max(len(row) for row in rows)
	img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
	pixels = img.load()
	for y, row in enumerate(rows):
		padded = row.ljust(width, ".")
		for x, ch in enumerate(padded):
			color = palette.get(ch)
			if color is not None:
				pixels[x, y] = color
	return img


def lighten(color: tuple[int, int, int, int], amount: float) -> tuple[int, int, int, int]:
	"""Осветляет RGB на amount (0..1). Alpha не трогает."""
	r, g, b, a = color
	nr = min(255, int(r + (255 - r) * amount))
	ng = min(255, int(g + (255 - g) * amount))
	nb = min(255, int(b + (255 - b) * amount))
	return (nr, ng, nb, a)


def make_cap(face_img: Image.Image, top_rows: int = 6, amount: float = 0.35) -> Image.Image:
	"""Делает cap-версию: копирует face и осветляет top_rows верхних строк,
	чтобы кромка визуально читалась как «козырёк над коллизией»."""
	img = face_img.copy()
	pixels = img.load()
	w, h = img.size
	for y in range(min(top_rows, h)):
		for x in range(w):
			r, g, b, a = pixels[x, y]
			pixels[x, y] = lighten((r, g, b, a), amount)
	return img


# ==================== LEGACY floor.png / wall.png ==================
# Оставлены совместимо с существующими тестами и preload'ами.
# Использовались как «универсальный» floor/wall до появления профилей.

LEGACY_FLOOR_PALETTE = {
	"F": (70, 62, 78, 255),
	"L": (95, 85, 105, 255),
	"d": (45, 40, 55, 255),
	"S": (30, 25, 40, 255),
}

LEGACY_FLOOR = [
	"SSSSSSSSSSSSSSSSSSSS",
	"SFLLFFFFFFSFFFFFFFFS",
	"SLFFFFFFdFSFFFdFFFFS",
	"SFFFFFdFFFSFFFFFFLFS",
	"SFFdFFFFFFSFLFFFFFFS",
	"SFFFFFFFLFSFFFFFFdFS",
	"SFFFFLFFFFSFFFFFFFFS",
	"SFFFFFFFFFSFdFFFFFLS",
	"SLFFFFFdFFSFFFFdFFFS",
	"SFFFdFFFFFSFFFFFFFFS",
	"SSSSSSSSSSSSSSSSSSSS",
	"SFFFFLFFFFSFFFdFFFFS",
	"SFdFFFFFFFSFFFFFFFFS",
	"SFFFFFFdFFSLFFFFFFdS",
	"SFFFFFFFFLSFFFFFFFFS",
	"SFFdFFFFFFSFFFLFFFFS",
	"SFFFFFFLFFSFdFFFFFFS",
	"SFFFFFFFFFSFFFFdFFFS",
	"SLFFdFFFFFSFFFFFFFFS",
	"SSSSSSSSSSSSSSSSSSSS",
]

LEGACY_WALL_PALETTE = {
	"B": (35, 28, 38, 255),
	"b": (22, 18, 26, 255),
	"L": (55, 45, 60, 255),
	"d": (15, 12, 18, 255),
	"M": (30, 22, 30, 255),
}

LEGACY_WALL = [
	"LLLLLLLLLLLLLLLLLLLL",
	"BBBBBBBBBbBBBBBBBBBB",
	"BBBBBBBBBbBBBBBBBBBB",
	"BBBMBBBBBbBBBBBBBMBB",
	"BBBBBBBBBbBBBMBBBBBB",
	"BdBBBBBBBbBBBBBBBBBB",
	"BBBBBBBBBbBBBBBBBBBB",
	"BBBBBBBBBbBBBBBBdBBB",
	"BBBBBBBBBbBBBBBBBBBB",
	"bbbbbbbbbbbbbbbbbbbb",
	"LLLLLLLLLLLLLLLLLLLL",
	"BBBBBBbBBBBBBBBBBBBB",
	"BBBBBBbBBBBMBBBBBBBB",
	"BBBMBBbBBBBBBBBBBBBB",
	"BBBBBBbBBBBBBBBBBBBB",
	"BBBBBBbBBBBBBBBBBBBB",
	"BBBBBBbBBBBBBBBBBBBB",
	"BBdBBBbBBBBBBBBBBMBB",
	"BBBBBBbBBBBBBBBBBBBB",
	"bbbbbbbbbbbbbbbbbbbb",
]


# ==================== FLOOR МАТЕРИАЛЫ ================================


def _wood_floor(dark: bool) -> tuple[list[str], dict]:
	"""Вертикальные доски 4 px шириной. Тёплая палитра.
	dark=True — тёмный кабинетный вариант."""
	if dark:
		pal = {
			"P": (52, 34, 22, 255),   # доска
			"H": (72, 52, 34, 255),   # блик
			"S": (18, 10, 6, 255),    # шов между досками
			"K": (30, 18, 10, 255),   # сучок
		}
	else:
		pal = {
			"P": (98, 66, 40, 255),
			"H": (128, 92, 60, 255),
			"S": (44, 28, 16, 255),
			"K": (66, 42, 22, 255),
		}
	# 5 досок по 4 px + 1-пиксельные швы между ними на позициях 3, 7, 11, 15, 19.
	rows: list[str] = []
	for y in range(20):
		row_chars: list[str] = []
		for x in range(20):
			if x % 4 == 3:
				row_chars.append("S")
			else:
				# доска: базовый P, с редким блик H и сучком K
				# используем детерминированный "шум" по (x, y)
				noise = ((x * 17 + y * 31) ^ (y * 5)) & 15
				if noise == 3:
					row_chars.append("H")
				elif noise == 7 and y % 5 == 2:
					row_chars.append("K")
				else:
					row_chars.append("P")
		rows.append("".join(row_chars))
	return rows, pal


def _corridor_stone() -> tuple[list[str], dict]:
	"""Легаси floor.png — холодные плитки 10×10 с крестовыми швами."""
	return LEGACY_FLOOR, LEGACY_FLOOR_PALETTE


def _light_stone_tile() -> tuple[list[str], dict]:
	"""Светлая керамическая плитка 10×10 без чередования, тёплая."""
	pal = {
		"T": (188, 176, 160, 255),
		"L": (218, 208, 192, 255),
		"d": (150, 140, 128, 255),
		"S": (108, 96, 82, 255),
	}
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			if x == 0 or x == 10 or y == 0 or y == 10:
				row.append("S")
			else:
				noise = ((x * 13 + y * 7) ^ (y * 3)) & 15
				if noise == 2:
					row.append("L")
				elif noise == 11:
					row.append("d")
				else:
					row.append("T")
		rows.append("".join(row))
	return rows, pal


def _reinforced_stone() -> tuple[list[str], dict]:
	"""Каменные плиты с металлическими заклёпками по углам."""
	pal = {
		"S": (68, 60, 58, 255),
		"L": (94, 84, 80, 255),
		"d": (44, 38, 36, 255),
		"J": (26, 22, 22, 255),   # шов
		"M": (180, 152, 100, 255),  # заклёпка (латунь)
		"m": (128, 100, 60, 255),
	}
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			if x == 0 or x == 10 or y == 0 or y == 10:
				row.append("J")
			elif (x, y) in {(2, 2), (12, 2), (2, 12), (12, 12), (7, 7), (17, 7), (7, 17), (17, 17)}:
				row.append("M")
			elif (x, y) in {(3, 2), (13, 2), (3, 12), (13, 12), (8, 7), (18, 7), (8, 17), (18, 17)}:
				row.append("m")
			else:
				noise = ((x * 19 + y * 11)) & 15
				if noise == 3:
					row.append("L")
				elif noise == 8:
					row.append("d")
				else:
					row.append("S")
		rows.append("".join(row))
	return rows, pal


def _stone_metal_grid() -> tuple[list[str], dict]:
	"""Металлическая решётка поверх камня — служебный коридор."""
	pal = {
		"S": (58, 52, 50, 255),
		"D": (36, 32, 30, 255),
		"G": (86, 74, 52, 255),   # медь
		"g": (60, 52, 34, 255),
		"H": (110, 96, 70, 255),
	}
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			# решётка каждые 4 px
			if x % 4 == 0 or y % 4 == 0:
				if x % 4 == 0 and y % 4 == 0:
					row.append("H")
				else:
					row.append("G" if (x + y) % 2 == 0 else "g")
			else:
				noise = ((x * 7 + y * 13) ^ y) & 7
				if noise == 2:
					row.append("D")
				else:
					row.append("S")
		rows.append("".join(row))
	return rows, pal


def _heat_stained_stone() -> tuple[list[str], dict]:
	"""Камень с ржаво-красными пятнами вокруг бойлерных."""
	pal = {
		"S": (56, 42, 34, 255),
		"L": (78, 58, 44, 255),
		"d": (32, 22, 18, 255),
		"R": (128, 60, 34, 255),   # ржавое пятно
		"r": (94, 44, 24, 255),
		"J": (22, 14, 10, 255),
	}
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			if x % 10 == 0 or y % 10 == 0:
				row.append("J")
			else:
				# «пятна» — круглые в определённых позициях
				dx = x - 6
				dy = y - 6
				d1 = dx * dx + dy * dy
				dx2 = x - 14
				dy2 = y - 14
				d2 = dx2 * dx2 + dy2 * dy2
				if d1 <= 4:
					row.append("R")
				elif d1 <= 8:
					row.append("r")
				elif d2 <= 3:
					row.append("R")
				elif d2 <= 7:
					row.append("r")
				else:
					noise = ((x * 5 + y * 11)) & 15
					if noise == 3:
						row.append("L")
					elif noise == 9:
						row.append("d")
					else:
						row.append("S")
		rows.append("".join(row))
	return rows, pal


def _damaged_tower_stone() -> tuple[list[str], dict]:
	"""Разрушенная плитка — трещины, отсутствующие куски."""
	pal = {
		"S": (72, 66, 78, 255),
		"L": (98, 88, 106, 255),
		"d": (46, 40, 54, 255),
		"C": (24, 20, 30, 255),   # трещина
		"J": (32, 26, 40, 255),
	}
	rows = []
	# паттерн трещин, зафиксированный сидом для детерминизма
	rng = random.Random(4242)
	crack_cells: set[tuple[int, int]] = set()
	# зигзаг-трещина
	cx, cy = 3, 4
	for _ in range(16):
		crack_cells.add((cx, cy))
		if rng.random() < 0.5:
			cx = min(19, cx + 1)
		else:
			cy = min(19, cy + 1)
	# вторая трещина
	cx, cy = 10, 14
	for _ in range(10):
		crack_cells.add((cx, cy))
		if rng.random() < 0.4:
			cx = min(19, cx + 1)
		else:
			cy = max(0, cy - 1)
	for y in range(20):
		row = []
		for x in range(20):
			if x == 0 or x == 10 or y == 0 or y == 10:
				row.append("J")
			elif (x, y) in crack_cells:
				row.append("C")
			else:
				noise = ((x * 7 + y * 17) ^ (y * 11)) & 15
				if noise == 2:
					row.append("L")
				elif noise == 9:
					row.append("d")
				else:
					row.append("S")
		rows.append("".join(row))
	return rows, pal


def _wet_basement_stone() -> tuple[list[str], dict]:
	"""Сырой пол подвала — холодная сине-зелёная палитра."""
	pal = {
		"S": (40, 52, 58, 255),
		"L": (56, 72, 78, 255),
		"d": (26, 34, 40, 255),
		"W": (30, 46, 52, 255),   # мокрое пятно
		"J": (14, 20, 24, 255),
	}
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			if x == 0 or x == 10 or y == 0 or y == 10:
				row.append("J")
			else:
				# «лужа» вокруг (5,5) и (14,15)
				d1 = (x - 5) ** 2 + (y - 5) ** 2
				d2 = (x - 14) ** 2 + (y - 15) ** 2
				if d1 <= 5 or d2 <= 5:
					row.append("W")
				else:
					noise = ((x * 11 + y * 5) ^ y) & 15
					if noise == 3:
						row.append("L")
					elif noise == 10:
						row.append("d")
					else:
						row.append("S")
		rows.append("".join(row))
	return rows, pal


def _cave_ground() -> tuple[list[str], dict]:
	"""Естественная земля/камень пещер. НЕ плиточный паттерн — органика."""
	pal = {
		"E": (50, 40, 30, 255),   # земля
		"L": (72, 60, 46, 255),
		"d": (32, 24, 18, 255),
		"R": (58, 50, 42, 255),   # камешек
		"r": (44, 36, 28, 255),
	}
	rng = random.Random(1337)
	pebbles: dict[tuple[int, int], str] = {}
	for _ in range(14):
		x = rng.randint(1, 18)
		y = rng.randint(1, 18)
		pebbles[(x, y)] = "R"
		if rng.random() < 0.6:
			pebbles[(x + 1, y)] = "r"
		if rng.random() < 0.3:
			pebbles[(x, y + 1)] = "r"
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			if (x, y) in pebbles:
				row.append(pebbles[(x, y)])
			else:
				noise = ((x * 13 + y * 7) ^ (x * 5)) & 15
				if noise == 2:
					row.append("L")
				elif noise == 9:
					row.append("d")
				else:
					row.append("E")
		rows.append("".join(row))
	return rows, pal


# ==================== WALL МАТЕРИАЛЫ ================================


def _plaster_wall() -> tuple[list[str], dict]:
	"""Светлая штукатурка со сколами."""
	pal = {
		"P": (152, 140, 120, 255),
		"L": (188, 176, 156, 255),
		"d": (122, 110, 92, 255),
		"c": (86, 74, 60, 255),   # скол
	}
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			noise = ((x * 13 + y * 7)) & 31
			if noise == 3:
				row.append("L")
			elif noise == 17:
				row.append("d")
			elif noise == 25:
				row.append("c")
			else:
				row.append("P")
		rows.append("".join(row))
	return rows, pal


def _wood_panel_wall() -> tuple[list[str], dict]:
	"""Вертикальные деревянные панели с горизонтальным молдингом."""
	pal = {
		"P": (78, 52, 32, 255),
		"H": (108, 76, 48, 255),
		"S": (34, 22, 14, 255),
		"M": (52, 34, 20, 255),   # молдинг
	}
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			if y in (0, 1, 18, 19):
				row.append("M")
			elif x % 5 == 4:
				row.append("S")
			else:
				noise = ((x * 11 + y * 3)) & 15
				if noise == 3:
					row.append("H")
				else:
					row.append("P")
		rows.append("".join(row))
	return rows, pal


def _tower_stone_wall() -> tuple[list[str], dict]:
	"""Легаси wall.png — классическая кирпичная кладка."""
	return LEGACY_WALL, LEGACY_WALL_PALETTE


def _technical_stone_wall() -> tuple[list[str], dict]:
	"""Тёмный камень с медными полосами — служебные стены."""
	pal = {
		"B": (42, 36, 42, 255),
		"b": (26, 22, 26, 255),
		"L": (58, 48, 54, 255),
		"d": (18, 14, 18, 255),
		"C": (128, 92, 52, 255),   # медная полоса
		"c": (86, 62, 34, 255),
	}
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			if y in (8, 11):
				row.append("C" if (x + y) % 2 == 0 else "c")
			elif y == 9 or y == 10:
				row.append("c")
			elif y == 0 or y == 19:
				row.append("b")
			elif x % 10 == 4:
				row.append("b")
			else:
				noise = ((x * 7 + y * 11)) & 15
				if noise == 2:
					row.append("L")
				elif noise == 10:
					row.append("d")
				else:
					row.append("B")
		rows.append("".join(row))
	return rows, pal


def _basement_brick_wall() -> tuple[list[str], dict]:
	"""Холодный сине-серый кирпич подвала."""
	pal = {
		"B": (46, 50, 58, 255),
		"b": (28, 32, 40, 255),
		"L": (62, 68, 78, 255),
		"d": (22, 26, 34, 255),
		"M": (46, 60, 50, 255),   # мох между швов
	}
	# кирпич 20x5 running bond (offset каждый 2-й ряд)
	rows = []
	for y in range(20):
		row = []
		row_idx = y // 5
		offset = 5 if row_idx % 2 == 1 else 0
		for x in range(20):
			# вертикальные швы каждые 10, со сдвигом
			seam_x = (x + offset) % 10
			if y % 5 == 4 or seam_x == 0:
				if (x * 3 + y) % 7 == 0:
					row.append("M")
				else:
					row.append("b")
			else:
				noise = ((x * 5 + y * 13)) & 15
				if noise == 2:
					row.append("L")
				elif noise == 10:
					row.append("d")
				else:
					row.append("B")
		rows.append("".join(row))
	return rows, pal


def _natural_cave_wall() -> tuple[list[str], dict]:
	"""Естественная скала — никакой кладки, только органика."""
	pal = {
		"S": (38, 30, 26, 255),
		"L": (62, 50, 40, 255),
		"d": (22, 16, 12, 255),
		"C": (10, 6, 4, 255),   # тёмная выемка
	}
	rng = random.Random(9001)
	pockets: set[tuple[int, int]] = set()
	for _ in range(6):
		cx = rng.randint(3, 16)
		cy = rng.randint(3, 16)
		for dy in (-1, 0, 1):
			for dx in (-1, 0, 1):
				if abs(dx) + abs(dy) <= 1 and rng.random() < 0.7:
					pockets.add((cx + dx, cy + dy))
	rows = []
	for y in range(20):
		row = []
		for x in range(20):
			if (x, y) in pockets:
				row.append("C")
			else:
				noise = ((x * 13 + y * 17) ^ (x * 3 + y * 5)) & 15
				if noise == 2:
					row.append("L")
				elif noise == 9:
					row.append("d")
				else:
					row.append("S")
		rows.append("".join(row))
	return rows, pal


# ==================== DOORWAY THRESHOLD =============================


def _doorway_threshold() -> tuple[list[str], dict]:
	"""Metallic полоса-порог 40×20, символизирующая переход между
	room material и corridor material. Тёмная центральная линия
	читается как «граница»."""
	pal = {
		"M": (110, 90, 60, 255),  # металл (латунь)
		"m": (74, 58, 34, 255),
		"L": (150, 122, 76, 255),
		"d": (54, 44, 26, 255),
		"C": (26, 20, 12, 255),   # центральная линия
	}
	rows = []
	for y in range(20):
		row = []
		for x in range(40):
			if y in (0, 19):
				row.append("d")
			elif y in (9, 10):
				row.append("C")
			elif y in (1, 18):
				row.append("m")
			else:
				noise = ((x * 5 + y * 7)) & 7
				if noise == 2:
					row.append("L")
				elif noise == 5:
					row.append("m")
				else:
					row.append("M")
		rows.append("".join(row))
	return rows, pal


# ==================== СБОРКА ==========================================


@dataclass
class Sprite:
	filename: str
	build: callable  # -> (rows, palette)


FLOOR_SPRITES: list[Sprite] = [
	Sprite("floor.png", lambda: (LEGACY_FLOOR, LEGACY_FLOOR_PALETTE)),
	Sprite("wood_floor.png", lambda: _wood_floor(False)),
	Sprite("dark_wood_floor.png", lambda: _wood_floor(True)),
	Sprite("corridor_stone.png", _corridor_stone),
	Sprite("light_stone_tile.png", _light_stone_tile),
	Sprite("reinforced_stone.png", _reinforced_stone),
	Sprite("stone_metal_grid.png", _stone_metal_grid),
	Sprite("heat_stained_stone.png", _heat_stained_stone),
	Sprite("damaged_tower_stone.png", _damaged_tower_stone),
	Sprite("wet_basement_stone.png", _wet_basement_stone),
	Sprite("cave_ground.png", _cave_ground),
]


WALL_SPRITES: list[Sprite] = [
	Sprite("wall.png", lambda: (LEGACY_WALL, LEGACY_WALL_PALETTE)),
	Sprite("plaster_wall.png", _plaster_wall),
	Sprite("wood_panel_wall.png", _wood_panel_wall),
	Sprite("tower_stone_wall.png", _tower_stone_wall),
	Sprite("technical_stone_wall.png", _technical_stone_wall),
	Sprite("basement_brick_wall.png", _basement_brick_wall),
	Sprite("natural_cave_wall.png", _natural_cave_wall),
]


DOORWAY_SPRITES: list[Sprite] = [
	Sprite("doorway_threshold.png", _doorway_threshold),
]


def _wall_cap_filename(face: str) -> str:
	stem = face[:-4]  # без .png
	return f"{stem}_cap.png"


def main() -> None:
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	total = 0
	for spr in FLOOR_SPRITES + DOORWAY_SPRITES:
		rows, palette = spr.build()
		img = render(rows, palette)
		out = OUT_DIR / spr.filename
		img.save(out)
		print(f"wrote {out} ({img.width}x{img.height})")
		total += 1
	for spr in WALL_SPRITES:
		rows, palette = spr.build()
		face = render(rows, palette)
		out_face = OUT_DIR / spr.filename
		face.save(out_face)
		print(f"wrote {out_face} ({face.width}x{face.height})")
		total += 1
		# wall.png — legacy, отдельного cap-варианта не имеет; для остальных
		# генерируем «cap»-версию с осветлённой верхней частью.
		if spr.filename == "wall.png":
			continue
		cap = make_cap(face)
		out_cap = OUT_DIR / _wall_cap_filename(spr.filename)
		cap.save(out_cap)
		print(f"wrote {out_cap} ({cap.width}x{cap.height})")
		total += 1
	print(f"total sprites: {total}")


if __name__ == "__main__":
	main()
