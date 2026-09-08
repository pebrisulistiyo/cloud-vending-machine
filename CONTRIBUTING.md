# Contributing

Solo project, but the workflow is written as if a team were on it. These
rules keep history readable and releases reproducible.

## Branching

Trunk-based development:

- `main` is always deployable. Nothing lands on it except through a PR.
- Feature branches are short-lived and named `feat/<thing>` or
  `fix/<thing>`.
- Branch protection comes from terraform-bootstrap: no force pushes, no
  deletions, conversation resolution required, `prevent_destroy` on the
  repo itself.
- Rebase or squash on merge. History on `main` is linear.

## Commits

Conventional commit prefixes, because releases are cut from tags and the
changelog is generated from history:

```
feat: add resource_type allowlist for gce
fix: resolve callback when approval arrives before workflow start
docs: document GCP unblock checklist
ci: add pip-audit to app-ci
chore: bump fastapi
```

## Releases (semver)

Releases are git tags in `vMAJOR.MINOR.PATCH` form:

- `MAJOR`: breaking API changes (request schema changes, removed resource
  types).
- `MINOR`: new resource types, new endpoints, new features.
- `PATCH`: fixes, docs, dependency bumps.

Pushing a tag runs `release.yml`: full gate chain (ruff, pytest, pip-audit,
Trivy block CRITICAL/HIGH), image build with the version baked in, push to
Artifact Registry tagged with both the version and the SHA, deploy to Cloud
Run when GCP is live, and a GitHub Release with generated notes.

```bash
git tag v1.2.0
git push origin v1.2.0
```

The app reports its version on `/health` (`version` field), injected at
build time from the tag.

## Security tooling

| Layer | Tool | Where |
|-------|------|-------|
| Secrets in code and history | gitleaks | pre-commit + app-ci (full history) |
| Static analysis | CodeQL (python) | app-ci |
| Dependency vulnerabilities | pip-audit | app-ci + release gates |
| Dependency updates | Dependabot | weekly PRs (pip + GitHub Actions) |
| Container image | Trivy, block CRITICAL/HIGH + SARIF | app-ci + release |
| Infrastructure | tflint, terraform fmt -check, actionlint | platform-ci |
| Input validation | pydantic allowlists + shell allowlists | app + provision.yml |

Run the local equivalents before pushing:

```bash
pre-commit run --all-files
cd app && ruff check . && python -m pytest tests -q && pip-audit
```

## Local development

See [docs/local-dev.md](docs/local-dev.md).
