# hypedora

Omarchy 4 „Quattro" pe Fedora 44, cu o singură comandă — un strat subțire peste
[omedora](https://github.com/AndrewGaspar/omedora) (branch `omedora-4`), care la
rândul lui e Omarchy pe Fedora. Tot ce e al nostru stă în `hypedora/`; restul
repo-ului e upstream neatins (vezi `hypedora/upstream-patches.txt` pentru
excepțiile care sunt PR-uri în curs).

## Instalare (Fedora 44 Workstation sau netinstall cu grupul Workstation)

```bash
curl -fsSL https://raw.githubusercontent.com/bsorescu/hypedora/hypedora/hypedora/boot.sh | bash
```

Apoi reboot → alege sesiunea **Omedora** în GDM.

## Structură

- `hypedora/boot.sh` — one-liner: preflight → installer-ul omedora-4 nemodificat → post-install
- `hypedora/post-install.sh` — overlay + tweaks de VM (doar sub `systemd-detect-virt`)
- `hypedora/vm/` — preflight host + rulare L4 (nested + VM KVM cu 3D) pe un laptop Fedora
- `hypedora/docs/` — cum ținem pasul cu omedora-4, riscuri cu declanșator
- `test/hypedora-*-test.sh` — testele noastre L1 (TAP, `bash test/hypedora-additive-test.sh`)

Decizii și research: vault Obsidian `hypedora/` (ADR-001).

## Stare

M1 (2026-08-23): comanda unică validată într-un VM KVM Fedora 44 (virgl, 1920×1080):
`curl | bash` → `RC=0`, reboot → sesiunea Omedora + shell-ul Quickshell pornesc
(bară, meniu, teme; 10 min idle fără crash); vezi vault `hypedora/sessions/`.
Setup-ul de sistem rulează din checkout (`OMEDORA_SETUP_FROM_REPO=1`) până când
COPR-ul `agaspar/omedora-4` publică un build cu fix-urile purtate de fork
(`hypedora/upstream-patches.txt`).
