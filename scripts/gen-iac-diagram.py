#!/usr/bin/env python3
"""Regenerate the EmpireOS vault Excalidraw diagram IaC-Dependency-Graph.excalidraw.md
from the as-built onprem-infra OpenTofu 3-state model (network -> opconnect -> compute).

Emits an Obsidian Excalidraw `parsed` markdown file with an uncompressed ```json drawing
block (the plugin reads it and re-compresses on next save). Deterministic layout, valid
schema, no hand-authored JSON.

Usage:
    python3 scripts/gen-iac-diagram.py [OUTPUT_PATH]
    IAC_DIAGRAM_OUT=/path/to/file.excalidraw.md python3 scripts/gen-iac-diagram.py

The node/edge model below is a SNAPSHOT of the as-built fleet as of 2026-06-12 (VMID
Scheme B, opconnect Option D, S3+SSE-KMS backend, prevent_destroy singletons). When the
fleet changes, re-derive ground truth via
    tofu -chdir=tofu/<state> graph
    tofu -chdir=tofu/<state> state list
and update the model below. Verified against the live tofu graph; see
docs/terraform-to-tofu-parity-matrix.md.
"""
import json
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else os.environ.get(
    "IAC_DIAGRAM_OUT",
    "/Users/fcx/Documents/EmpireOS/Excalidraw/09-Homelab/IaC-Dependency-Graph.excalidraw.md",
)
T = 1749740000000  # fixed 'updated' stamp (Excalidraw regenerates on edit)

_seed = [7001]
def sid():
    _seed[0] += 1
    return _seed[0]

elements = []
text_index = []  # (id, text) for the ## Text Elements section

# palette (Excalidraw-native)
C = {
    "net":   ("#2f9e44", "#d3f9d8"),
    "opc":   ("#e8590c", "#ffe8cc"),
    "comp":  ("#1971c2", "#d0ebff"),
    "op1p":  ("#9c36b5", "#f3d9fa"),
    "sec":   ("#e03131", "#ffe3e3"),
    "back":  ("#495057", "#e9ecef"),
    "ink":   ("#1e1e1e", "#ffffff"),
}

def rect(x, y, w, h, stroke, bg, group=None, sw=2, rounded=True, dashed=False):
    e = {
        "id": f"r{sid()}", "type": "rectangle", "x": x, "y": y, "width": w, "height": h,
        "angle": 0, "strokeColor": stroke, "backgroundColor": bg, "fillStyle": "solid",
        "strokeWidth": sw, "strokeStyle": "dashed" if dashed else "solid", "roughness": 1,
        "opacity": 100, "groupIds": ([group] if group else []), "frameId": None,
        "roundness": ({"type": 3} if rounded else None), "seed": sid(), "version": 1,
        "versionNonce": sid(), "isDeleted": False, "boundElements": [], "updated": T,
        "link": None, "locked": False,
    }
    elements.append(e)
    return e["id"]

def text(x, y, w, s, size=16, color="#1e1e1e", align="center", tid=None):
    nlines = s.count("\n") + 1
    h = int(size * 1.25 * nlines)
    eid = tid or f"t{sid()}"
    e = {
        "id": eid, "type": "text", "x": x, "y": y, "width": w, "height": h,
        "angle": 0, "strokeColor": color, "backgroundColor": "transparent", "fillStyle": "solid",
        "strokeWidth": 2, "strokeStyle": "solid", "roughness": 1, "opacity": 100,
        "groupIds": [], "frameId": None, "roundness": None, "seed": sid(), "version": 1,
        "versionNonce": sid(), "isDeleted": False, "boundElements": [], "updated": T,
        "link": None, "locked": False, "text": s, "fontSize": size, "fontFamily": 1,
        "textAlign": align, "verticalAlign": "top", "containerId": None,
        "originalText": s, "autoResize": True, "lineHeight": 1.25,
    }
    elements.append(e)
    text_index.append((eid, s))
    return eid

def node(x, y, w, h, label, ckey, size=15, sub_dashed=False):
    """A colored box with centered label."""
    stroke, bg = C[ckey]
    rect(x, y, w, h, stroke, bg, dashed=sub_dashed)
    nlines = label.count("\n") + 1
    th = int(size * 1.25 * nlines)
    text(x + 8, y + (h - th) / 2, w - 16, label, size=size, color="#1e1e1e", align="center")

def arrow(x1, y1, x2, y2, color="#1e1e1e", dashed=False, sw=2):
    dx, dy = x2 - x1, y2 - y1
    e = {
        "id": f"a{sid()}", "type": "arrow", "x": x1, "y": y1, "width": abs(dx), "height": abs(dy),
        "angle": 0, "strokeColor": color, "backgroundColor": "transparent", "fillStyle": "solid",
        "strokeWidth": sw, "strokeStyle": "dashed" if dashed else "solid", "roughness": 1,
        "opacity": 100, "groupIds": [], "frameId": None, "roundness": {"type": 2}, "seed": sid(),
        "version": 1, "versionNonce": sid(), "isDeleted": False, "boundElements": [], "updated": T,
        "link": None, "locked": False, "points": [[0, 0], [dx, dy]], "lastCommittedPoint": None,
        "startBinding": None, "endBinding": None, "startArrowhead": None, "endArrowhead": "arrow",
    }
    elements.append(e)

# ---------- title + banner ----------
text(60, 30, 1900, "IaC Dependency Graph  ·  onprem-infra (OpenTofu, as-built 2026-06-12)", size=28, align="left", tid="main-title")
text(60, 78, 1900, "tofu/network  →  tofu/opconnect  →  tofu/compute   ·   generated from `tofu graph` + state list   ·   apply in order, destroy reverse", size=16, align="left", tid="subtitle")

# ---------- state container backdrops (drawn first = behind) ----------
COLY = 140
COLH = 1080
rect(40, COLY, 470, COLH, C["net"][0], "#ebfbee", sw=2)      # NETWORK
rect(540, COLY, 540, COLH, C["opc"][0], "#fff4e6", sw=2)     # OPCONNECT
rect(1110, COLY, 850, COLH, C["comp"][0], "#e7f5ff", sw=2)   # COMPUTE
text(40, COLY + 12, 470, "STATE 1 — tofu/network\nfoundation · exports STABLE IDs", size=17, color=C["net"][0], tid="hdr-net")
text(540, COLY + 12, 540, "STATE 2 — tofu/opconnect\nsecrets root · prevent_destroy", size=17, color=C["opc"][0], tid="hdr-opc")
text(1110, COLY + 12, 850, "STATE 3 — tofu/compute\nthe fleet (A3: one .tf per service)", size=17, color=C["comp"][0], tid="hdr-comp")

# ---------- NETWORK column ----------
nx, nw = 70, 410
node(nx, 230, nw, 64, "data.unifi_network\n\"Home Lab\" (VLAN 40) → network_id", "net")
node(nx, 330, nw, 64, "download_file\nubuntu cloud image", "net")
node(nx, 430, nw, 70, "vm.ubuntu_template\nVMID 9001 (clone source)", "net")
node(nx, 540, nw, 64, "download_file\ndebian-12 LXC template (vztmpl)", "net")
NET_OUT = (nx, 660, nw, 110)
node(*NET_OUT, "outputs — STABLE IDs ONLY\nhomelab_network_id\nubuntu_template_vm_id\ndebian_lxc_template_file_id", "net", size=14)
arrow(nx + nw/2, 394, nx + nw/2, 430, C["net"][0])          # cloud image -> template

# ---------- OPCONNECT column ----------
ox, ow = 560, 500
node(ox, 230, ow, 56, "data.terraform_remote_state → network", "comp", size=14, sub_dashed=True)
node(ox, 320, ow, 70, "module.opconnect\nVM 1101 · proxmox-vm · prevent_destroy", "opc")
node(ox, 420, ow, 60, "opconnect_cloud_init\nuser_data + vendor_data", "opc", size=14)
node(ox, 510, ow, 64, "opconnect_dns\nunifi_client + unifi_dns_record", "opc", size=14)
node(ox, 604, ow, 56, "ansible_host / ansible_group\nopconnect", "opc", size=14)
node(ox, 700, ow, 62, "tls_private_key.ansible (ED25519)\n→ null_resource ssh_key_writeback", "opc", size=14)
OPC_1P = (ox, 800, ow, 70)
node(*OPC_1P, "1Password  (op CLI, account mode)\nOption D — NO onepassword provider here", "op1p", size=13)
node(ox, 900, ow, 78, "1Password Connect installed on the VM\nby Ansible (connect-api + connect-sync);\nserves Day-2 secrets", "op1p", size=12, sub_dashed=True)
arrow(ox + ow/2, 286, ox + ow/2, 320, C["comp"][0], dashed=True)   # remote_state -> VM
arrow(ox + ow/2, 480, ox + ow/2, 420, C["opc"][0])                 # cloud_init -> VM (up)
arrow(ox + ow/2, 390, ox + ow/2, 510, C["opc"][0])                 # VM -> dns
arrow(ox + ow/2, 574, ox + ow/2, 604, C["opc"][0])                 # dns -> ansible_host
arrow(ox + ow/2, 762, ox + ow/2, 800, C["opc"][0])                 # tls key -> 1Password

# ---------- COMPUTE column ----------
cx, cw = 1130, 810
node(cx, 230, 390, 56, "data.terraform_remote_state → network", "comp", size=13, sub_dashed=True)
COMP_1PKEY = (cx + 420, 230, 390, 56)
node(*COMP_1PKEY, "data.onepassword_item\nansible_ssh_key (via Connect)", "op1p", size=13, sub_dashed=True)
# service bundle (representative pattern)
node(cx, 320, 810, 50, "PER-SERVICE MODULE PATTERN  (one .tf file each)", "comp", size=14)
by = 388
node(cx, by, 250, 76, "module.<svc>\nproxmox VM (or LXC)\n→ live IP", "comp", size=13)
node(cx + 280, by, 250, 64, "<svc>_cloud_init\nuser+vendor\n(injects ansible pubkey)", "comp", size=12)
node(cx + 560, by, 250, 64, "<svc>_dns\nunifi_client + dns_record", "comp", size=12)
node(cx + 280, by + 96, 530, 56, "ansible_host.compute[<svc>] → ansible_group\n(homelab · application_servers · monitoring · postgresql)", "comp", size=12)
arrow(cx + 250, by + 38, cx + 280, by + 32, C["comp"][0])          # module -> cloud_init
arrow(cx + 280, by + 50, cx + 250, by + 50, C["comp"][0])          # cloud_init -> module (pubkey)
arrow(cx + 530, by + 32, cx + 560, by + 32, C["comp"][0])          # cloud_init -> dns (via module IP)
arrow(cx + 125, by + 76, cx + 400, by + 96, C["comp"][0])          # VM -> ansible_host
arrow(cx + 685, by + 64, cx + 600, by + 96, C["comp"][0])          # dns -> ansible_host
text(cx, by + 162, 810, "the hot web:  VM  →  IP  →  DNS (reservation + A record)  →  ansible_host  →  inventory\npostgresql (LXC) injects the ansible pubkey via ssh_pubkey, not a cloud_init module", size=13, color=C["comp"][0], align="left", tid="hotweb")
# the actual services
node(cx, 620, 810, 86, "SERVICES (state list):  gitlab VM 1201 (protected) · postgresql LXC 2101 (protected)\nmealie 1301 · tandoor 1302 · immich 1303 · runitup 1304  — disposable via count(disabled_workloads)\nimmich photo library on UNAS NFS .137; all OS/DB on local-zfs", "comp", size=13)
# secrets
node(cx, 730, 810, 96, "onepassword_item ×7 (Day-2 secrets, consumed by Ansible)\ngitlab_root_password · gitlab_runner_token · postgresql_admin\nimmich_db_password · mealie_db_user · tandoor_db_user · tandoor_secret_key", "sec", size=12)
arrow(cx + 195, 286, cx + 195, 320, C["comp"][0], dashed=True)     # remote_state -> pattern
arrow(cx + 615, 286, cx + 545, 320, C["op1p"][0], dashed=True)     # 1P key -> cloud_init

# ---------- cross-state arrows ----------
arrow(NET_OUT[0] + NET_OUT[2], 700, ox, 250, C["net"][0], sw=3)            # network outputs -> opconnect remote_state
arrow(NET_OUT[0] + NET_OUT[2], 715, cx, 250, C["net"][0], sw=3)           # network outputs -> compute remote_state
arrow(OPC_1P[0] + OPC_1P[2], 835, COMP_1PKEY[0] + 50, 286, C["op1p"][0], dashed=True, sw=3)  # 1P writeback -> compute 1P-key
text(1000, 250, 130, "remote_state\n(stable IDs)", size=12, color=C["net"][0], tid="lbl-rs")
text(1010, 560, 180, "via 1Password\nConnect", size=12, color=C["op1p"][0], tid="lbl-1p")

# ---------- backend anchor (bottom) ----------
by2 = 1250
rect(40, by2, 1920, 96, C["back"][0], C["back"][1], sw=2)
text(60, by2 + 14, 1880, "STATE BACKEND — S3 + SSE-KMS  ·  bucket tmpx-tfstate-065094257518-use2  ·  keys onprem/proxmox/{network,opconnect,compute}/terraform.tfstate", size=15, color=C["back"][0], align="left", tid="backend-1")
text(60, by2 + 52, 1880, "native S3 lockfile (no DynamoDB)  ·  enforced AES-GCM state encryption  ·  assume_role 065094257518:OrganizationAccountAccessRole  ·  patched UniFi 0.42.0-fcx1 via .tofurc", size=14, color=C["back"][0], align="left", tid="backend-2")
arrow(280, COLY + COLH, 280, by2, C["back"][0], dashed=True)
arrow(810, COLY + COLH, 810, by2, C["back"][0], dashed=True)
arrow(1500, COLY + COLH, 1500, by2, C["back"][0], dashed=True)

# ---------- emit ----------
drawing = {
    "type": "excalidraw", "version": 2,
    "source": "https://github.com/zsviczian/obsidian-excalidraw-plugin",
    "elements": elements,
    "appState": {"gridSize": None, "viewBackgroundColor": "#ffffff"},
    "files": {},
}

te_lines = []
for eid, s in text_index:
    te_lines.append(f"{s} ^{eid}\n")
text_elements = "\n".join(te_lines)

md = f"""---
excalidraw-plugin: parsed
tags: [excalidraw, homelab, iac, opentofu, ansible]
---

==⚠  Switch to EXCALIDRAW VIEW in the MORE OPTIONS menu of this document. ⚠==

# Infrastructure as Code Dependency Graph

As-built dependency graph of the FusionCloudX onprem-infra repo (OpenTofu 3-state), regenerated 2026-06-12 from `tofu graph` + `tofu state list`. States: tofu/network -> tofu/opconnect -> tofu/compute. See [[VM-Inventory]] and the repo's `docs/terraform-to-tofu-parity-matrix.md`.

# Excalidraw Data

## Text Elements
{text_elements}
%%
## Drawing
```json
{json.dumps(drawing, ensure_ascii=False)}
```
%%
"""

with open(OUT, "w") as f:
    f.write(md)

print(f"wrote {OUT}")
print(f"elements: {len(elements)} (rect={sum(1 for e in elements if e['type']=='rectangle')}, text={sum(1 for e in elements if e['type']=='text')}, arrow={sum(1 for e in elements if e['type']=='arrow')})")
print(f"text_index entries: {len(text_index)}")
# self-validate JSON round-trips
json.loads(json.dumps(drawing))
print("json round-trip OK")
