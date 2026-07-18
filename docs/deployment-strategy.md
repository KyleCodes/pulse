# Deployment Strategy

How artifacts are built, stored, versioned, and rolled — locally today, and the same model on a real VM.

## The model

An artifact is an immutable image `pulse-<service>:<tag>`. The compose file never names a version — it reads **tag pointers** from `.env` (`API_TAG=…`). Every deployment action is one of two verbs:

- **Deploy** = build/push a new tag, move the pointer, recreate one service.
- **Rollback** = move the pointer to a tag that already exists, recreate. No rebuild.

Blast radius is always one service; every prior tag remains available.

## Today (single machine)

The docker daemon's content-addressed image store *is* the registry. `make deploy SERVICE=api` builds `pulse-api:<git-sha>`, repoints `API_TAG` in `.env`, and recreates only api. `make rollback SERVICE=api TAG=…` repoints to an existing tag. `docker images pulse-api` lists the artifact history.

**Known limitation, accepted at this scale:** with `build:` blocks in the compose file, tags are immutable by convention only — `make up` rebuilds from the working tree and re-tags as whatever the pointer currently says. A hosted registry (below) removes this class of problem.

## On a bare VM (the production shape — same verbs, different storage)

1. **A registry appears** (ghcr, ECR, or self-hosted `registry:2`). The build side — CI, or a dev machine until CI exists — runs `docker build -t <registry>/pulse-api:<sha> && docker push`.
2. **The VM's compose file loses every `build:` block.** Images become registry-qualified and pinned: `image: <registry>/pulse-api:${API_TAG}`. The VM never builds — it only pulls immutable artifacts.
3. **The pointer becomes a committed change.** `.env` (or the pin in the compose file itself — cosmetic difference) is versioned in git, so repo state fully determines what's running.
4. **Deploy:** push image → commit the pointer change → on the VM: `git pull && docker compose pull && docker compose up -d <service>`. No SSH-for-debugging; one operator command (or a webhook/cron for pull-based automation).
5. **Rollback:** `git revert` the pointer commit → `up -d`. The old image is already in the registry.

This is GitOps-lite: deploy history *is* git history, and "what's running in prod" is answered by reading a file, not by SSHing in.

## Triggers

| Trigger | Change |
|---|---|
| Second machine / first real VM | Hosted registry; strip `build:` from the deployed compose file; commit pointer changes |
| Team wants hands-off deploys | CI runs build+push+pointer-commit; VM pulls on webhook or interval |
| Multiple environments | One pointer file per env (`.env.staging`, `.env.prod`), same compose file |
