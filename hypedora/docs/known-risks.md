# Riscuri cu declanșator (nu se acționează preventiv)

| Declanșator | Semnal | Răspuns |
|---|---|---|
| Qt 6.11.2 pe Fedora 44 | `dnf info qt6-qtbase` ≥ 6.11.2 / Bodhi | quickshell `28771c7` crapă (omarchy #7750) → rebuild `quickshell.spec` la 0.3.1 sau COPR `errornointernet/quickshell`; ADR nou dacă schimbăm sursa |
| Build lipsă în COPR `agaspar/omedora-4` (`auto_prune`) | `dnf install` eșuează pe un pachet omedora | COPR-oglindă `bsorescu/hypedora` din `omedora/packaging/copr/` (`build-repo.sh`), `OMEDORA_COPR_OWNER=bsorescu` |
| Fedora 45 (GA 2026-10-20) | laptopul trece pe F45 | COPR-ul omedora-4 are doar f44 → decizie separată (ADR) |
| Quickshell nu randează pe virgl | suita L4-VM: `00-session` ok dar `30-visual` fail / bară lipsă | **infirmat la M1 (2026-08-23)**: bara randează pe virgl la 1920×1080; `30-visual` pică doar pe golden upstream învechit |
| COPR-ul publică un build cu fix-urile fork-ului | `omarchy-apply-system` + gate-ul snapper apar în payload-ul RPM | scoate `OMEDORA_SETUP_FROM_REPO=1` din `hypedora/boot.sh` și `hypedora/vm/run-l4-vm.sh` |
