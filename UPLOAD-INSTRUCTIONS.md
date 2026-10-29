# Assignment 5 — GitHub Upload Instructions

Target repository: [Varun7687/Assignment-5](https://github.com/Varun7687/Assignment-5), branch `main`.

These instructions describe publishing source only. They do not authorize deployment, changes to the current AWS account, or deletion of resources. Nothing was pushed while this package was created.

## 1. Keep your working infrastructure private

Extract the ZIP into a separate clean folder. Do not extract over your existing state-bearing Terraform directory. Keep the existing Terraform state, private `terraform.tfvars`, AWS/SSO configuration, and SSH private keys outside this public folder.

The archive contains a top-level `Assignment-5/` folder. Upload that folder's contents to the repository root, not a second nested `Assignment-5/` directory. Keep the root app/template/requirements beside `terraform/` because Terraform references them.

## 2. Check the public file set

Include:

* Root README, project/source/upload documentation, `.gitignore`, and `architecture.png`.
* `app.py`, `requirements.txt`, `templates/`, and reference `SQL/`.
* Terraform source, IAM policies, scripts, `.terraform.lock.hcl`, and `terraform.tfvars.example`.
* Offline tests and the evidence checklist.

Exclude actual tfvars, state/backups, saved plans/JSON, `.terraform/`, `.aws/`, `.env`, passwords/tokens, private keys, dumps, and unredacted evidence. The example file's placeholders are intentional; do not put real values into the public example.

## 3. Recommended Git workflow

Use Git Bash or your normal Git terminal. Clone into a new publishing directory; do not reuse the active infrastructure working directory.

```bash
git clone https://github.com/Varun7687/Assignment-5.git Assignment-5-publish
cd Assignment-5-publish
git switch main
```

Copy the extracted package contents, including `.gitignore` and the Terraform lockfile, into this clone. Preserve `.git/`. Review replacement of the repository's existing README rather than merging it blindly.

```bash
git status --short --untracked-files=all
git add --dry-run .
```

Inspect every proposed file. Then stage and inspect the actual diff before committing:

```bash
git add .
git diff --cached --name-only
git diff --cached
```

Do not paste the full staged diff into a public chat if it contains private values. `.gitignore` does not remove secrets already tracked or in Git history; if any secret was previously published, stop, revoke/rotate it, and follow the approved history-remediation process.

After you have reviewed the staged files and chosen to publish:

```bash
git commit -m "Add Assignment 5 landing-zone source and documentation"
git push origin main
```

These commands are instructions for you; they were not executed by the assistant. Use your normal credential manager. Never embed a PAT in a URL, command, README, or screenshot.

## 4. Verify GitHub display

Confirm that the README's PNG renders, `terraform/terraform.tfvars.example` contains only placeholders for private settings, `.terraform.lock.hcl` is included, and no actual state, plans, private variables, private keys, or credentials are visible. The evidence checklist should remain clearly uncompleted until genuine testing is done.

For later infrastructure use, compare changes first and deliberately update the original state-bearing working directory. Do not initialize an unrelated local state to manage the same AWS resources. A fresh plan and mentor approval are still required.
