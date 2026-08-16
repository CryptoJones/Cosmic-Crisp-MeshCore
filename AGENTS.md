# Rules for agents (and humans) working in this repo

1. **Never push without a green local CI run.** Run `scripts/ci-local.sh` on
   the Mac (it mirrors `.github/workflows/ci.yml` step for step) and only push
   when it prints `ALL CI STEPS PASSED LOCALLY`. A red GitHub CI email means
   this rule was broken. If the workflow changes, change the script in the
   same commit.
2. Public repo: feature branch + PR to `main`, never a direct push to `main`.
3. Every PR body ends with: `Proudly Made in Nebraska. Go Big Red! 🌽 https://xkcd.com/2347/`
4. The reference for protocol byte layouts is the `meshcore` Python library;
   pin any new layout with a unit test in `Packages/MeshCoreKit/Tests`.
5. Don't claim a change is in a PR unless `git diff` shows it. Verify edits
   landed (grep the file) before describing them.
