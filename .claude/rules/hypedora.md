# hypedora — reguli pentru Claude Code (strat aditiv peste omedora-4)

Acest repo e un fork al `AndrewGaspar/omedora` (branch urmărit: `omedora-4`); `hypedora`
= branch-ul nostru. **Citește întâi** `hypedora/README.md`, apoi contextul din vault-ul
Obsidian (`~/Documents/obsidian-claude/hypedora/`): `context/hypedora/current-state.md`,
`plans/2026-08-22-m1-validare-omedora-4-in-vm.md` (planul activ, cu checkbox-uri),
`architecture/hypedora-design.md`, `decisions/ADR-001-*.md`.

- **Principiul aditiv:** scrii doar în `hypedora/`, `test/hypedora-*` și `.claude/rules/hypedora.md`.
  Orice fișier upstream atins (inclusiv `CLAUDE.md`, `AGENTS.md`) trebuie listat în
  `hypedora/upstream-patches.txt` și devine PR către `AndrewGaspar/omedora` (`-B omedora-4`).
  Gardian: `bash test/hypedora-additive-test.sh`.
- Ghidurile upstream (`CLAUDE.md`, `AGENTS.md`, `omedora/AGENTS.md`) rămân valabile pentru ce atingem din el.
- Testele noastre: `for t in test/hypedora-*-test.sh; do bash "$t" || echo "FAIL $t"; done`.
- Artefacte (qcow2, iso, screenshot-uri) nu se comit; rezultatele merg în vault (`hypedora/sessions/`, `sessions/assets/`).
