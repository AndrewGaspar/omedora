# Upstream tracking

- `upstream` = `https://github.com/AndrewGaspar/omedora.git`, branch urmărit: `omedora-4`
  (Gaspar face rebase + force-push; noi nu urmărim `basecamp/omarchy` direct).
- Când apare un pin nou (`git fetch upstream --tags | grep omedora-base-`):
  ```bash
  git fetch upstream
  git rebase upstream/omedora-4        # patch-urile noastre sunt puține: hypedora/ + PR-uri în curs
  bash test/hypedora-additive-test.sh
  git push --force-with-lease origin hypedora
  ```
- PR-uri upstream: orice modificare la un fișier din afara `hypedora/` se listează în
  `hypedora/upstream-patches.txt` și se trimite ca PR (`gh pr create -R AndrewGaspar/omedora -B omedora-4`).
  După merge + rebase, se scoate din listă.
