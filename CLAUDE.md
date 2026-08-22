# hypedora — instrucțiuni pentru Claude Code

Acest repo e un fork al `AndrewGaspar/omedora` (branch urmărit: `omedora-4`); `hypedora`
= branch-ul nostru. **Citește întâi** `hypedora/README.md`, apoi contextul din vault-ul
Obsidian (`~/Documents/obsidian-claude/hypedora/`): `context/hypedora/current-state.md`,
`plans/2026-08-22-m1-validare-omedora-4-in-vm.md` (planul activ, cu checkbox-uri),
`architecture/hypedora-design.md`, `decisions/ADR-001-*.md`.

Reguli specifice:
- **Principiul aditiv:** scrii doar în `hypedora/` și `test/hypedora-*`. Orice fișier
  upstream atins trebuie listat în `hypedora/upstream-patches.txt` și devine PR către
  `AndrewGaspar/omedora` (`-B omedora-4`). Gardian: `bash test/hypedora-additive-test.sh`.
- Upstream-ul are propriile ghiduri (`AGENTS.md`, `omedora/AGENTS.md`) — valabile pentru
  ce atingem din el.
- Testele noastre: `for t in test/hypedora-*-test.sh; do bash "$t" || echo "FAIL $t"; done`.
- Artefacte (qcow2, iso, screenshot-uri) nu se comit; rezultatele merg în vault
  (`hypedora/sessions/`, `sessions/assets/`).
