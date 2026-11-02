# lardo

Run [Lark / Feishu CLI](https://github.com/larksuite/cli) in Docker. Keep its data in one Docker volume. There is no need to install Node.js, npm, Go, or the CLI on your host.

- Source: [nmnmcc/lardo](https://github.com/nmnmcc/lardo)
- Image: `ghcr.io/nmnmcc/lardo`
- Platforms: `linux/amd64` and `linux/arm64`

The image uses the official release files and checks them with the upstream SHA-256 file. It keeps the upstream MIT license. It does not run the npm setup tool or install AI skills. It does not change your host PATH, shell files, or agent folders. If you need AI skills, choose and install them on your own.

## Quick start

You need Docker and Docker Compose v2 or later.

```sh
export LARK_IMAGE=ghcr.io/nmnmcc/lardo:latest
docker compose pull

# Open the URL from the command in your host browser to set up an app.
docker compose run --rm lark config init --new

# Open the next URL in your host browser to log in.
docker compose run --rm lark auth login --recommend

# Each command uses the same saved app and login data.
docker compose run --rm lark auth status
docker compose run --rm lark calendar +agenda
```

Keep `LARK_IMAGE` set in the same shell for later commands. Run `docker compose pull` again to update. You can use a version tag, such as `:1.0.98`, or an image digest instead of `:latest`.

Login uses a URL and polls for the result. You do not need a browser in the container or an open host port. If you already have an app, run `config init` without `--new` and follow the prompts. Choose the Lark brand during setup if you use Lark instead of Feishu.

## Build on your machine

```sh
# Do not set LARK_IMAGE when you want to use the local image.
unset LARK_IMAGE
docker compose build --pull
docker compose run --rm lark --version
docker compose run --rm lark config init --new
```

The local build uses version `1.0.98` by default. To use another release:

```sh
CLI_VERSION=1.0.98 docker compose build --pull
```

Replace the version number as needed. Build or pull a new image to update the CLI. Do not run `lark-cli update` in the container.

## How the data is kept

Compose uses a named Docker volume, **`lardo-data`**, at `/data`. Removing a container with `--rm`, pulling an image, or rebuilding an image does not remove this volume. The CLI does not write its settings or cache into this source folder.

| Path in the container | Use |
| --- | --- |
| `/data/.lark-cli` | App settings, users, logs, and state |
| `/data/.local/share` | Encrypted secrets and the `master.key` file |
| Other paths under `/data` | HOME and XDG user files and cache |
| `/tmp` | Memory storage; removed when the container stops |
| `/work` | Read only by default; mount a folder here for file tasks |

Saving only `.lark-cli` is not enough. On Linux, the CLI saves secrets and the key in a different data folder. This image sets `HOME`, `LARKSUITE_CLI_CONFIG_DIR`, and `LARKSUITE_CLI_DATA_DIR` so that both folders are in the same volume. Keep the whole volume when you make a backup. Do not change these paths one at a time or copy macOS keychain files into the Linux image.

The volume holds both the encrypted secrets and their key. Treat a backup like a password. `docker compose down` keeps the volume. **`docker compose down -v`, deleting the volume, or pruning unused volumes can delete your login data.** You would then need to set up the app and log in again.

To keep work and personal accounts apart, use a different volume name. Use that same name for each command:

```sh
LARK_DATA_VOLUME=lardo-work docker compose run --rm lark config init --new
LARK_DATA_VOLUME=lardo-work docker compose run --rm lark auth status
```

Compose runs as user and group `10001:10001`, with a read-only root file system, no Linux capabilities, and no new privileges. It does not mount your HOME, source tree, or Docker socket, and it does not open any ports. The image does not create anonymous volumes. If you use `docker run` on its own, you must mount `/data` to keep your data.

## Files to upload or download

Mount only the folder you need. For example, keep downloaded files in `exports`:

```sh
mkdir -p exports
docker compose run --rm -v "$PWD/exports:/work" lark drive --help

# Use a read-only mount for input files.
docker compose run --rm -v "$PWD/exports:/work:ro" lark drive --help
```

Replace `drive --help` with your command. Use `/work/...` paths in CLI arguments. On Linux, an output folder must allow user `10001:10001` to write. Do not mount your whole HOME. A watch or event command must keep running; its process stops when the container stops.

## Back up and restore

Stop all commands that use the volume before a backup. The example below uses the local image. Replace `lardo:local` with `$LARK_IMAGE` if you use GHCR.

```sh
# This file will hold keys and secrets.
docker run --rm --user 0:0 --entrypoint tar \
  --mount type=volume,src=lardo-data,dst=/data,readonly \
  lardo:local -C /data -czf - . > lardo-data.tar.gz

# Restore into a new volume, with the same file owners and permissions.
docker volume create lardo-restored
docker run --rm -i --user 0:0 --entrypoint tar \
  --mount type=volume,src=lardo-restored,dst=/data \
  lardo:local -C /data -xzpf - < lardo-data.tar.gz
LARK_DATA_VOLUME=lardo-restored docker compose run --rm lark auth status
```

## GitHub Actions

The workflow builds and tests both platforms before it pushes each version to GHCR.

| Event | Result |
| --- | --- |
| Push to the default branch | Sync new and missing old versions |
| Push to another branch or a pull request | Test the latest stable version; do not log in or push |
| Daily at 02:23 UTC (10:23 in Taipei) | Sync new and missing versions; rebuild the latest stable image |
| Manual run | Sync all missing versions, or build one chosen version |

In **Actions → Docker → Run workflow**, leave `version` blank to sync. Set `version` to a release such as `1.0.98`, `v1.0.98`, or `1.0.86-beta.0` to build just that version. The `backfill` switch controls old versions and is on by default. Use the default branch to publish.

The sync scans all non-draft upstream releases. A release must have a checksum file and release files for both Linux platforms. This includes pre-release versions. Existing version tags are skipped, except for the latest stable version. Each run handles up to 128 versions, with up to 8 jobs at once. Later runs pick up any remaining or failed versions. A failed old version does not stop other versions from being published.

All versions use the same base image, tools, and tests. No extra build tools are needed for old versions. The test handles the old CLI flag for a test secret; the real data paths stay under `/data`.

Each image gets its upstream version tag, such as `:1.0.98`. Only the latest stable release also gets `:latest`. Building an old or pre-release version does not move `latest` back. A version tag may be rebuilt with a newer base image; use a digest to pin the full image. If a download, checksum, or test fails, that version is not pushed.

Actions use fixed commit IDs. The workflow uses `GITHUB_TOKEN`; no personal token or Docker Hub secret is needed. The images include build records and a software bill of materials (SBOM). Tests run without a network, use fake app secrets, and check that a new container can read the saved secret. They also check the user, read-only root, and lack of npm and AI skill files. Test volumes are removed on exit. Real account login and live API calls are not part of these tests.

If you copy this repo, enable Actions and allow it to write GitHub Packages. The image name will use your lower-case owner and repo name. A new GHCR package may be private at first; set it to Public in its package settings for pulls without login. GitHub may delay scheduled runs or pause them in an inactive repo.

## Check the build

```sh
docker compose config --quiet
docker compose build
bash tests/smoke.sh lardo:local "linux/$(docker version --format '{{.Server.Arch}}')"
```

See the upstream [setup code](https://github.com/larksuite/cli/blob/main/scripts/install-wizard.js), [config paths](https://github.com/larksuite/cli/blob/main/internal/core/workspace.go), and [Linux secret storage](https://github.com/larksuite/cli/blob/main/internal/keychain/keychain_other.go). See also the Docker docs for [multi-platform Actions](https://docs.docker.com/build/ci/github-actions/multi-platform/) and [volumes](https://docs.docker.com/engine/storage/volumes/).
