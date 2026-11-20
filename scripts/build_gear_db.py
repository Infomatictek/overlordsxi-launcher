#!/usr/bin/env python3
"""
SoulspireXI Gear Database Generator for soulspire_gear (Ashita v4)

Parses LandSandBoat SQL tables (c:/dev/server/sql/*) and SoulspireXI custom
SQL/Lua modules (C:/soulspirexi/modules/custom/*) to produce compact, fast-loading
Lua data tables under addons/ashita4/soulspire_gear/data/.
"""

import re
from pathlib import Path

SERVER_DIR = Path(r"C:\dev\server")
OVERLORDS_DIR = Path(r"C:\soulspirexi")
OUT_DIR = Path(__file__).resolve().parent.parent / "addons" / "ashita4" / "soulspire_gear" / "data"


def parse_mods_enum(mod_path: Path):
    """Parse scripts/enum/mod.codegen.lua for MOD_NAME -> modId."""
    mod_by_name = {}
    mod_by_id = {}
    text = mod_path.read_text(encoding="utf-8", errors="ignore")
    for m in re.finditer(r"^\s*([A-Z0-9_]+)\s*=\s*(-?\d+)\s*,", text, re.MULTILINE):
        name, mid = m.group(1), int(m.group(2))
        if mid >= 0:
            mod_by_name[name] = mid
            if mid not in mod_by_id:
                mod_by_id[mid] = name
    # Custom SoulspireXI mod 1198 (Orphic Egg Faerie Refresh)
    mod_by_name["FAERIE_REFRESH"] = 1198
    mod_by_id[1198] = "FAERIE_REFRESH"
    return mod_by_name, mod_by_id


def parse_items_enum(item_enum_path: Path):
    """Parse scripts/enum/item.lua for ITEM_NAME -> itemId."""
    items_by_name = {}
    if not item_enum_path.exists():
        return items_by_name
    text = item_enum_path.read_text(encoding="utf-8", errors="ignore")
    for m in re.finditer(r"^\s*([A-Z0-9_]+)\s*=\s*(\d+)\s*,", text, re.MULTILINE):
        items_by_name[m.group(1)] = int(m.group(2))
    return items_by_name


def parse_sql_equipment(sql_path: Path):
    """Parse item_equipment.sql."""
    items = {}
    text = sql_path.read_text(encoding="utf-8", errors="ignore")
    pattern = re.compile(
        r"INSERT INTO `item_equipment` VALUES\s*\(\s*(\d+)\s*,\s*'((?:\\'|[^'])*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)"
    )
    for m in pattern.finditer(text):
        item_id = int(m.group(1))
        name = m.group(2).replace("\\'", "'")
        level = int(m.group(3))
        ilevel = int(m.group(4))
        jobs = int(m.group(5))
        shield_size = int(m.group(7))
        slot = int(m.group(9))
        rslot = int(m.group(10))
        su_level = int(m.group(12))
        items[item_id] = {
            "id": item_id,
            "name": name,
            "level": level,
            "ilevel": ilevel,
            "jobs": jobs,
            "shield": shield_size,
            "slot": slot,
            "rslot": rslot,
            "su": su_level,
            "skill": 0,
            "dmg": 0,
            "delay": 0,
            "mods": {},
            "pet": {},
        }
    return items


def parse_sql_weapons(sql_path: Path, items: dict):
    """Parse item_weapon.sql and attach skill/dmg/delay to items."""
    text = sql_path.read_text(encoding="utf-8", errors="ignore")
    pattern = re.compile(
        r"INSERT INTO `item_weapon` VALUES\s*\(\s*(\d+)\s*,\s*'((?:\\'|[^'])*)'\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*\)"
    )
    for m in pattern.finditer(text):
        item_id = int(m.group(1))
        skill = int(m.group(3))
        delay = int(m.group(10))
        dmg = int(m.group(11))
        if item_id in items:
            items[item_id]["skill"] = skill
            items[item_id]["dmg"] = dmg
            items[item_id]["delay"] = delay


def parse_sql_mods(sql_path: Path, items: dict):
    """Parse item_mods.sql."""
    text = sql_path.read_text(encoding="utf-8", errors="ignore")
    pattern = re.compile(r"INSERT INTO `item_mods` VALUES\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*\)")
    for m in pattern.finditer(text):
        item_id = int(m.group(1))
        mod_id = int(m.group(2))
        val = int(m.group(3))
        if item_id in items and val != 0:
            items[item_id]["mods"][mod_id] = items[item_id]["mods"].get(mod_id, 0) + val


def parse_sql_pet_mods(sql_path: Path, items: dict):
    """Parse item_mods_pet.sql."""
    text = sql_path.read_text(encoding="utf-8", errors="ignore")
    pattern = re.compile(
        r"INSERT INTO `item_mods_pet` VALUES\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*(\d+)\s*\)"
    )
    for m in pattern.finditer(text):
        item_id = int(m.group(1))
        mod_id = int(m.group(2))
        val = int(m.group(3))
        pet_type = int(m.group(4))
        if item_id in items and val != 0:
            p = items[item_id]["pet"].setdefault(pet_type, {})
            p[mod_id] = p.get(mod_id, 0) + val


def parse_sql_latents(sql_path: Path, items: dict):
    """Parse item_latents.sql."""
    latents = {}
    text = sql_path.read_text(encoding="utf-8", errors="ignore")
    pattern = re.compile(
        r"INSERT INTO `item_latents` VALUES\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)"
    )
    for m in pattern.finditer(text):
        item_id = int(m.group(1))
        mod_id = int(m.group(2))
        val = int(m.group(3))
        lat_id = int(m.group(4))
        lat_param = int(m.group(5))
        if item_id in items and val != 0:
            latents.setdefault(item_id, []).append(
                {"mod": mod_id, "v": val, "lat": lat_id, "p": lat_param}
            )
    return latents


def parse_sql_augments(sql_path: Path):
    """Parse augments.sql."""
    augments = {}
    text = sql_path.read_text(encoding="utf-8", errors="ignore")
    pattern = re.compile(
        r"INSERT INTO `augments` VALUES\s*\(\s*(\d+)\s*,\s*(-?\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)"
    )
    for m in pattern.finditer(text):
        aug_id = int(m.group(1))
        mult = int(m.group(2))
        mod_id = int(m.group(3))
        val = int(m.group(4))
        is_pet = int(m.group(5))
        pet_type = int(m.group(6))
        if mod_id != 0 and val != 0:
            entry = {"mod": mod_id, "v": val, "m": mult}
            if is_pet != 0:
                entry["pet"] = pet_type
            augments.setdefault(aug_id, []).append(entry)
    return augments


def parse_gear_sets(gear_sets_path: Path, items_by_name: dict, mod_by_name: dict):
    """Parse scripts/globals/gear_sets.lua."""
    gearsets = {}
    if not gear_sets_path.exists():
        return gearsets
    text = gear_sets_path.read_text(encoding="utf-8", errors="ignore")
    block_pattern = re.compile(r"    \[(\d+)\]\s*=[^\n]*\n    \{(.*?)\n    \},", re.DOTALL)
    for m in block_pattern.finditer(text):
        set_id = int(m.group(1))
        body = m.group(2)
        min_eq_m = re.search(r"minEquipped\s*=\s*(\d+)", body)
        max_eq_m = re.search(r"maxEquipped\s*=\s*(\d+)", body)
        req_m = re.search(r"reqItem\s*=\s*xi\.item\.([A-Z0-9_]+)", body)
        min_eq = int(min_eq_m.group(1)) if min_eq_m else 2
        max_eq = int(max_eq_m.group(1)) if max_eq_m else 0
        req_id = items_by_name.get(req_m.group(1)) if req_m else None

        items_m = re.search(r"items\s*=\s*\{(.*?)\}", body, re.DOTALL)
        member_ids = []
        if items_m:
            for im in re.finditer(r"xi\.item\.([A-Z0-9_]+)", items_m.group(1)):
                iid = items_by_name.get(im.group(1))
                if iid:
                    member_ids.append(iid)

        mods_m = re.search(r"mods\s*=\s*\{(.*)\}", body, re.DOTALL)
        set_mods = []
        if mods_m:
            for mm in re.finditer(r"\{\s*xi\.mod\.([A-Z0-9_]+)\s*,\s*(-?\d+)\s*\}", mods_m.group(1)):
                mid = mod_by_name.get(mm.group(1))
                val = int(mm.group(2))
                if mid and val != 0:
                    set_mods.append({"mod": mid, "v": val})

        if member_ids and set_mods:
            gearsets[set_id] = {
                "min": min_eq,
                "max": max_eq,
                "req": req_id,
                "items": member_ids,
                "mods": set_mods,
            }
    return gearsets


def apply_overlords_custom_sql(items: dict, latents: dict):
    """Apply SoulspireXI custom SQL item overrides (eos_companion.sql, blm_necro_spec.sql, dnc_chakram_spec.sql)."""
    if 18256 in items:
        items[18256]["level"] = 1
        items[18256]["jobs"] = 524288
        items[18256]["mods"] = {1198: 1}
        latents.pop(18256, None)

    for item in items.values():
        if item["skill"] == 7:
            item["jobs"] |= 8

    dnc_chakrams = [
        18246, 18171, 17284, 17289, 19203, 17283, 18134, 18135,
        17285, 17279, 18231, 17286, 17295, 18245, 19261, 19770,
        21340, 18692, 18693, 18694, 21368,
    ]
    for cid in dnc_chakrams:
        if cid in items:
            items[cid]["jobs"] = 262144

    chakram_stats = {
        18246: (10, 16, 260, {11: 2, 26: 4}),
        18171: (None, 22, 260, None),
        17284: (None, 28, 260, None),
        17289: (None, 30, 255, None),
        19203: (None, 36, 260, None),
        17283: (None, 38, 260, None),
        18134: (None, 40, 255, None),
        18135: (None, 42, 250, None),
        17285: (None, 48, 255, None),
        17279: (None, 50, 250, None),
        18231: (None, 53, 250, {9: 3, 26: 6}),
        17286: (None, 58, 250, None),
        17295: (None, 60, 245, None),
        18245: (75, 56, 192, None),
        19261: (75, 58, 196, None),
        21340: (75, 66, 250, {24: 15, 26: 15, 365: 5}),
        19770: (75, 68, 255, None),
        18692: (75, 82, 270, {24: 25, 26: 25, 840: 15}),
        18693: (75, 76, 230, {26: 22, 14: 10, 365: 8}),
        18694: (75, 80, 250, {9: 12, 14: 12, 421: 12}),
        21368: (75, 85, 260, {345: 500, 73: 10, 26: 20}),
    }
    for cid, (lvl, dmg, delay, extra_mods) in chakram_stats.items():
        if cid in items:
            if lvl is not None:
                items[cid]["level"] = lvl
                items[cid]["ilevel"] = 0
            items[cid]["dmg"] = dmg
            items[cid]["delay"] = delay
            if extra_mods:
                items[cid]["mods"].update(extra_mods)


def parse_soulspire_ws_catalog(ws_catalog_path: Path):
    """Parse C:/soulspirexi/modules/custom/lua/soulspire_ws_catalog.lua."""
    ws_list = []
    if not ws_catalog_path.exists():
        return ws_list
    text = ws_catalog_path.read_text(encoding="utf-8", errors="ignore")
    skill_map = {
        "HAND_TO_HAND": 1,
        "DAGGER": 2,
        "SWORD": 3,
        "GREAT_SWORD": 4,
        "AXE": 5,
        "GREAT_AXE": 6,
        "SCYTHE": 7,
        "POLEARM": 8,
        "KATANA": 9,
        "GREAT_KATANA": 10,
        "CLUB": 11,
        "STAFF": 12,
        "ARCHERY": 25,
        "MARKSMANSHIP": 26,
        "THROWING": 27,
    }
    entry_pattern = re.compile(r"\[(\d+)\]\s*=\s*\{\s*id\s*=\s*(\d+),(.*?)\n\s*\},", re.DOTALL)
    for m in entry_pattern.finditer(text):
        ws_id = int(m.group(2))
        body = m.group(3)
        key_m = re.search(r"key\s*=\s*'([^']+)'", body)
        name_m = re.search(r"name\s*=\s*'((?:\\'|[^'])+)'", body)
        skill_m = re.search(r"skill\s*=\s*xi\.skill\.([A-Z0-9_]+)", body)
        type_m = re.search(r"wsType\s*=\s*'([^']+)'", body)
        hits_m = re.search(r"numHits\s*=\s*(\d+)", body)
        crit_m = re.search(r"critVaries\s*=\s*true", body)
        wsc_m = re.search(r"wsc\s*=\s*\{([^}]*)\}", body)

        wsc = {}
        if wsc_m:
            for wm in re.finditer(r"([a-z]+)\s*=\s*([0-9.]+)", wsc_m.group(1)):
                wsc[wm.group(1).upper()] = float(wm.group(2))

        ws_list.append({
            "id": ws_id,
            "key": key_m.group(1) if key_m else f"ws_{ws_id}",
            "name": name_m.group(1).replace("\\'", "'") if name_m else f"WS {ws_id}",
            "skill": skill_map.get(skill_m.group(1), 0) if skill_m else 0,
            "kind": type_m.group(1) if type_m else "physical",
            "hits": int(hits_m.group(1)) if hits_m else 1,
            "crit": bool(crit_m),
            "wsc": wsc,
        })
    return ws_list


def write_mods_lua(out_path: Path, mod_by_id: dict):
    lines = [
        "-- SoulspireXI Server Mod IDs (generated by scripts/build_gear_db.py)",
        "local t = {}",
        "local byName = {}",
    ]
    for mid in sorted(mod_by_id.keys()):
        name = mod_by_id[mid]
        lines.append(f"t[{mid}] = '{name}'")
    lines += [
        "for id, name in pairs(t) do byName[name] = id end",
        "return { ById = t, ByName = byName }",
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")


def write_items_lua(out_path: Path, items: dict):
    lines = [
        "-- SoulspireXI Equippable Items Database (generated by scripts/build_gear_db.py)",
        "local t = {};",
        "(function()",
    ]
    count = 0
    for iid in sorted(items.keys()):
        it = items[iid]
        if it["slot"] == 0:
            continue
        if count > 0 and count % 1500 == 0:
            lines.append("end)();")
            lines.append("(function()")
        count += 1
        parts = [
            f"level={it['level']}",
            f"jobs={it['jobs']}",
            f"slot={it['slot']}",
        ]
        if it["rslot"]:
            parts.append(f"rslot={it['rslot']}")
        if it["su"]:
            parts.append(f"su={it['su']}")
        if it["skill"]:
            parts.append(f"skill={it['skill']}")
        if it["dmg"]:
            parts.append(f"dmg={it['dmg']}")
        if it["delay"]:
            parts.append(f"delay={it['delay']}")
        if it["shield"]:
            parts.append(f"shield={it['shield']}")
        if it["mods"]:
            mparts = [f"[{k}]={v}" for k, v in sorted(it["mods"].items())]
            parts.append("mods={" + ",".join(mparts) + "}")
        if it["pet"]:
            pparts = []
            for ptype, pmods in sorted(it["pet"].items()):
                pm = ",".join(f"[{k}]={v}" for k, v in sorted(pmods.items()))
                pparts.append(f"[{ptype}]={{{pm}}}")
            parts.append("pet={" + ",".join(pparts) + "}")
        lines.append(f"t[{iid}]={{" + ",".join(parts) + "};")
    lines += [
        "end)();",
        "return t;",
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")


def write_latents_lua(out_path: Path, latents: dict):
    lines = [
        "-- SoulspireXI Item Latents Database (generated by scripts/build_gear_db.py)",
        "local t = {}",
        "(function()",
    ]
    for iid in sorted(latents.keys()):
        lparts = []
        for l in latents[iid]:
            lparts.append(f"{{mod={l['mod']},v={l['v']},lat={l['lat']},p={l['p']}}}")
        lines.append(f"t[{iid}]={{" + ",".join(lparts) + "}")
    lines += [
        "end)()",
        "return t",
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")


def write_augments_lua(out_path: Path, augments: dict):
    lines = [
        "-- SoulspireXI Augments Database (generated by scripts/build_gear_db.py)",
        "local t = {}",
        "(function()",
    ]
    for aid in sorted(augments.keys()):
        aparts = []
        for a in augments[aid]:
            pet_str = f",pet={a['pet']}" if "pet" in a else ""
            aparts.append(f"{{mod={a['mod']},v={a['v']},m={a['m']}{pet_str}}}")
        lines.append(f"t[{aid}]={{" + ",".join(aparts) + "}")
    lines += [
        "end)()",
        "return t",
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")


def write_gearsets_lua(out_path: Path, gearsets: dict):
    lines = [
        "-- SoulspireXI Gear Set Bonuses (generated by scripts/build_gear_db.py)",
        "local t = {}",
        "(function()",
    ]
    for sid in sorted(gearsets.keys()):
        gs = gearsets[sid]
        items_str = ",".join(str(x) for x in gs["items"])
        mods_str = ",".join(f"{{mod={m['mod']},v={m['v']}}}" for m in gs["mods"])
        req_str = f",req={gs['req']}" if gs["req"] else ""
        lines.append(
            f"t[{sid}]={{min={gs['min']},max={gs['max']}{req_str},items={{{items_str}}},mods={{{mods_str}}}}}"
        )
    lines += [
        "end)()",
        "return t",
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")


def write_weaponskills_lua(out_path: Path, ws_list: list):
    lines = [
        "-- SoulspireXI Weaponskills Catalog (generated by scripts/build_gear_db.py)",
        "local t = {}",
        "(function()",
    ]
    for ws in ws_list:
        wsc_str = ",".join(f"{k}={v}" for k, v in sorted(ws["wsc"].items()))
        crit_str = ",crit=true" if ws["crit"] else ""
        name_esc = ws["name"].replace("'", "\\'")
        lines.append(
            f"t[{ws['id']}]={{id={ws['id']},key='{ws['key']}',name='{name_esc}',skill={ws['skill']},kind='{ws['kind']}',hits={ws['hits']}{crit_str},wsc={{{wsc_str}}}}}"
        )
    lines += [
        "end)()",
        "return t",
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    mod_by_name, mod_by_id = parse_mods_enum(SERVER_DIR / "scripts" / "enum" / "mod.codegen.lua")
    items_by_name = parse_items_enum(SERVER_DIR / "scripts" / "enum" / "item.lua")

    items = parse_sql_equipment(SERVER_DIR / "sql" / "item_equipment.sql")
    parse_sql_weapons(SERVER_DIR / "sql" / "item_weapon.sql", items)
    parse_sql_mods(SERVER_DIR / "sql" / "item_mods.sql", items)
    parse_sql_pet_mods(SERVER_DIR / "sql" / "item_mods_pet.sql", items)
    latents = parse_sql_latents(SERVER_DIR / "sql" / "item_latents.sql", items)
    augments = parse_sql_augments(SERVER_DIR / "sql" / "augments.sql")
    gearsets = parse_gear_sets(SERVER_DIR / "scripts" / "globals" / "gear_sets.lua", items_by_name, mod_by_name)
    apply_overlords_custom_sql(items, latents)
    ws_list = parse_soulspire_ws_catalog(OVERLORDS_DIR / "modules" / "custom" / "lua" / "soulspire_ws_catalog.lua")

    used_mods = set()
    for it in items.values():
        used_mods.update(it["mods"].keys())
        for pm in it["pet"].values():
            used_mods.update(pm.keys())
    for llist in latents.values():
        for l in llist:
            used_mods.add(l["mod"])
    for alist in augments.values():
        for a in alist:
            used_mods.add(a["mod"])
    for gs in gearsets.values():
        for m in gs["mods"]:
            used_mods.add(m["mod"])
    filtered_mods = {mid: name for mid, name in mod_by_id.items() if mid in used_mods or mid < 600}

    write_mods_lua(OUT_DIR / "mods.lua", filtered_mods)
    write_items_lua(OUT_DIR / "items.lua", items)
    write_latents_lua(OUT_DIR / "latents.lua", latents)
    write_augments_lua(OUT_DIR / "augments.lua", augments)
    write_gearsets_lua(OUT_DIR / "gearsets.lua", gearsets)
    write_weaponskills_lua(OUT_DIR / "weaponskills.lua", ws_list)
    print(
        f"Generated SoulspireXI gear DB: {len(items)} items, {len(filtered_mods)} mods, "
        f"{len(latents)} latent items, {len(augments)} augments, {len(gearsets)} gearsets, {len(ws_list)} weaponskills."
    )


if __name__ == "__main__":
    main()
