# theriety GitHub Actions runners: preparation only

**Blocked, not deployed.** This source scaffold is versioned in `alvis/.bots` as a local-only preparation change; it does not deploy runners. The intended deployment host is dot's original computer only. This checkout is a preparation workspace, not that host. Two official Linux x64 runner distributions were reported present outside the original source directory on 2026-10-13, with neither locally registered. Those runtime archives and binaries were not transferred here. No registration, listener, workflow, service, autostart, credential handling, or push is part of this change. `configure` and `start` intentionally exit unsuccessfully before reading any token. `stop` is an explicit unsupported operation, not a claim that externally started runners were stopped.

## Intended configuration

- Organization: `https://github.com/theriety`
- Names: `theriety-oai-1`, `theriety-oai-2`
- Custom label: `theriety-oai`; retain GitHub's default platform labels
- Intended org runner-group repository access: all repositories, subject to GitHub permissions and public-repository controls. No group or access setting changed.
- Runtime root on the intended deployment host: `/workspace/shared/theriety-runners`, outside the source checkout
- Separate `runner`, `home`, and `tmp` directories per runner
- Manual operation only; no services, cron, restart loop, or boot integration

A label routes jobs; it does not establish a security boundary. A shared process sandbox is not a VM. Workflows using a persistent runner may compromise later jobs on that runner. Two separate directories do not solve that risk. Public repositories and untrusted pull requests particularly require careful access controls; the all-repositories preference does not authorize bypassing them.

## Commands

Run from this directory:

```sh
./runners.sh verify    # verify the pre-downloaded archive against pinned SHA-256
./runners.sh status    # local presence only; no credentials or remote API access
./runners.sh install   # offline extraction; refuses existing runtime trees
./runners.sh configure # blocked; reads no credential and registers nothing
./runners.sh start     # blocked; starts no listener
./runners.sh stop      # unsupported until a safe listener manager is implemented
```

`install` is a reusable offline preparation command for the intended deployment host, not a downloader or upgrade operation. It requires the official archive at the fixed downloads path and does not overwrite either existing tree, including a dangling symlink at a runner path. The original host's existing extracted distributions were reported verified independently against all 9,394 regular files in the archive. Dependency installation was not attempted. Linux x64 is the only packaged target here. The runtime path is fixed; no host-detection or deployment authorization mechanism is implemented.

### Recovery after an interrupted installation

Extraction is not transactional: a failed `mkdir` or `tar`, or an interrupted process, can leave one or both runner trees incomplete. The next `install` refuses any existing runner path before extracting either tree. This refusal is intentional protection for files that may include runner state. `verify` checks only the archive; `status` checks only file presence. Neither proves an extracted tree is complete, unused, or safe to remove, even when a listener binary is present and a registration file is absent.

On the intended host, under separate authorization, preserve the failed command's diagnostics and inspect both named paths without following symlinks. Establish ownership, whether another installation is in progress, and whether any external process or registration uses either tree. Do not retry while another writer is active. If provenance or use is uncertain, stop and leave the paths unchanged; this scaffold cannot stop external processes or determine remote registration.

For paths confirmed to belong only to the failed, unused preparation attempt, preserve each entire tree by moving it to a new, private quarantine location outside Git and outside the two fixed runner paths. Use a same-filesystem move that refuses an existing destination; verify that the move succeeded and retained the contents before proceeding. Never merge into a quarantine directory, follow a symlink target, delete credentials, or remove an existing working installation to clear the guard. A symlink or unexpected path type needs separate investigation, not this tree-move procedure. Quarantined contents may contain sensitive state and must remain private.

Only after both fixed runner paths are absent, the original failure cause is corrected, and the archive passes verification may an authorized offline retry proceed. If one tree is a valid existing installation, leave it in place: this two-tree installer intentionally cannot repair only its sibling. There is no automatic cleanup, resume, rollback, or force option. Keep preserved trees until their disposition is separately decided. These instructions do not authorize recovery actions or activation in this preparation workspace.

## Integrity

Pinned release: [actions/runner v2.338.0](https://github.com/actions/runner/releases/tag/v2.338.0)

Archive: `actions-runner-linux-x64-2.338.0.tar.gz`

SHA-256, reported matching the downloaded official release metadata's asset digest on the original host:

```text
af4b794c1bc41d73d40535e3fe092a39f9679cd8d965954c2aca25a05ca41d32
```

Archive location on the intended deployment host: `/workspace/shared/theriety-runners/downloads/actions-runner-linux-x64-2.338.0.tar.gz`

Hash verification establishes that bytes match the pinned digest; it is not a general assurance that self-hosted workflows are safe. Archive integrity and extracted binaries have not been reverified in this preparation checkout because they were not transferred.

## Activation blocker

An earlier attempt to create an isolated network namespace on the original host failed with a `NETLINK_ROUTE` / `Operation not permitted` error. This preparation does not retry or route around that restriction. Even a successfully created empty network namespace would lack the outbound HTTPS access a GitHub runner needs. An approved architecture must provide constrained egress while preventing access to host-local services, metadata endpoints, sibling jobs and private networks.

This is not a blanket GitHub connectivity failure: on 2026-10-14, curl to `api.github.com` returned HTTP 200 and an unauthenticated GraphQL POST reached GitHub with HTTP 403 (rate limit). A subsequent device-login attempt ended with the execution-system error `automatic approval review was cancelled`, with no saved login. The cause is unknown. These are supplied historical observations, not connectivity or authentication tests performed for this commit.

There is no runtime override for the activation block and no shared-network launcher. Shared-network runner risks have not been explicitly accepted. Shared networking would be a weaker alternative requiring a new explicit risk decision; it is documented here only, not activated. Platform networking or security settings must not be changed as an implicit part of this setup.

## Work remaining before activation

1. Resolve an approved isolated execution and network architecture with the host platform; do not disable or bypass its security restrictions.
2. Prefer disposable execution environments between jobs. Review cross-job persistence, filesystem mounts, environment, resource limits and container-job requirements. Test the actual runner environment.
3. Confirm organization administration authority and runner-group access policy, including the implications for public repositories and untrusted workflows.
4. Separately authorize and implement credential/registration handling. Keep GH CLI admin credentials outside Git AND outside all workflow mounts and environments. Registration material must never appear in committed files, logs, shell history, README examples or workflow YAML. `.gitignore` is only defense in depth.
5. Implement supervised manual start/stop with per-runner process identity checks and cleanup, then verify both online runners and an authorized test job. Do not install autostart. Verify removal and recovery paths before claiming completion.

No admin token belongs in a runner environment. Runner-generated credentials will necessarily have their own runtime security requirements; no secret transport or storage flow is implemented in this scaffold.

## Official references

- [GitHub self-hosted runner reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [Runner-group access](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/manage-access)
- [GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use)

## Validation record

Supplied historical evidence from the original host, 2026-10-13:

- `bash -n` passed for the manager script
- Official archive SHA-256 matched; both existing extractions matched every regular file
- `status` found both binaries and no `.runner` registration files
- `configure` and `start` exited nonzero without any registration or listener
- `stop` exited nonzero without signaling any process
- No network isolation retry, workflow execution, dependency installation or remote change

`install` extraction logic was not re-executed against the preexisting runtime trees. The full runner lifecycle is unimplemented and untested, intentionally blocked rather than silently weakened. The original host's results above are not reused as current validation.

Supplied historical preparation-workspace validation on 2026-10-14:

- `bash -n` passed for the manager script; `status` reported no binaries or registration files.
- `configure`, `start`, `stop`, and unknown commands exited nonzero; missing-archive `verify` and `install` failed closed. No actual runtime tree was created.
- Temporary copies with only the runtime root and digest replaced passed harmless fixture extraction, directory-permission checks, existing-tree and dangling-symlink refusal, and digest-mismatch rejection. This does not verify the official archive or a runner installation.
- A focused credential-pattern scan of the three text files found no matches; no dedicated secret scanner or ShellCheck was available.
- Sandbox operation and network isolation remain unverified in this executor. Validation utilities are kept outside the checkout; no test script or test command is included.

Current isolated-checkout validation on 2026-10-14:

- All three supplied input hashes matched before editing. Only this README changed from that input; the manager and ignore rules remain byte-identical.
- `bash -n` and the generic coding scanner passed. TypeScript analysis found no applicable packages. The scanner is advisory; source and recovery guidance also received semantic review.
- Twenty-eight temporary fixture invocations passed across CLI dispatch, argument rejection, archive integrity and symlink rejection, extraction and private directory modes, status presence reporting, existing-tree protection, and injected directory-creation/extraction failures.
- A failed extraction preserved a partial tree; retry refused it without modifying its contents. A fixture-only quarantine and retry preserved the partial contents and produced both new trees. No recovery action was performed on the intended host.
- Bash traces reached all 35 executable lines and all five functions. Manual syntactic inventory covered 45 statements (41 simple and four compound) and 31 explicit branch outcomes. These are trace-backed manual measurements, not AST-certified coverage, MC/DC, or deployed-runner validation.
- Fixture archives, traces, and validation scripts remain outside Git. The official archive, actual runner lifecycle, concurrent installers, and network isolation were not tested here.

These checks validate preparation behavior only. They do not validate or authorize activation on any host.
