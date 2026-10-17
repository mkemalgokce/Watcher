<p align="center">
  <img src=".github/assets/icon.png" width="128" height="128" alt="Watcher icon">
</p>

<h1 align="center">Watcher</h1>

<p align="center">
  A free, open-source HTTP(S) debugging proxy for macOS.<br>
  Capture, decrypt, inspect, mock and modify the traffic of your Mac, iOS Simulators, iPhones, iPads and Android devices.
</p>

<p align="center">
  <a href="https://github.com/mkemalgokce/watcher/actions/workflows/ci.yml"><img src="https://github.com/mkemalgokce/watcher/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/mkemalgokce/watcher/releases/latest"><img src="https://img.shields.io/github/v/release/mkemalgokce/watcher?include_prereleases&sort=semver" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-lightgrey.svg" alt="macOS 14 or later">
  <a href="https://github.com/sponsors/mkemalgokce"><img src="https://img.shields.io/badge/sponsor-%E2%99%A5-ea4aaa.svg" alt="Sponsor"></a>
</p>

<p align="center">
  <a href="https://github.com/mkemalgokce/watcher/releases/latest"><b>Download</b></a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#command-line">Command line</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

Watcher is a native SwiftUI app with a command line tool for scripts and an MCP server for AI agents.

## Features

- **Capture**: HTTP/1.1 and HTTP/2 (ALPN), HTTPS decryption with a local root certificate and per-host certificates,
  SSL Proxying include and exclude lists, a SOCKS5 listener, WebSocket frames, Server-Sent Events and streamed bodies.
- **Inspect**: request and response side by side; headers, query, form and multipart parameters, cookies, raw and hex views;
  previews for images, HTML (offline), PDF, audio and video, GraphQL and Protobuf/gRPC; JWT and Base64 decoding; timing;
  a diff of any two responses.
- **Large bodies**: tree-sitter colours only the visible lines of JSON, HTML/XML, CSS and JavaScript, so a 30 MB response stays
  responsive.
- **Filter**: one search field with tokens for method, status, content type, host, and where to look for text (URL, headers,
  body or anywhere); a sidebar of apps and domains.
- **Modify**: Breakpoints (edit, continue, abort), Map Local, Map Remote, Block and Allow Lists, Scripting (JavaScriptCore),
  DNS Spoofing, Reverse Proxy, External Proxy (HTTP, SOCKS, PAC), Network Throttling and No Caching. Rules match by wildcard,
  regex, method, GraphQL operation or sending app, and can be grouped in folders.
- **Compose**: build or repeat requests (JSON, form, multipart, GraphQL, files), import a cURL command, mock a response.
- **Export**: HAR, CSV, session files and workspaces; code as cURL, Swift, Python, JavaScript, Go, Ruby and PHP; Charles session
  and settings import.
- **Devices**: trust the certificate on this Mac, iOS Simulators, iPhone and iPad (profile and QR code) and Android (`adb`);
  turn the macOS system proxy on and off, restored on quit and after a crash.
- **Automation**: `watcher-cli` for headless capture and rules, and an MCP server (`watcher-cli mcp`) for AI agents.

## Requirements

macOS 14 or later. Release builds are for Apple silicon; building from source needs Xcode 26 or later.

## Install

Download `Watcher-<version>.dmg` from the [latest release](https://github.com/mkemalgokce/watcher/releases/latest), open it
and drag Watcher to Applications.

Releases are signed with a Developer ID and notarized by Apple, so Watcher opens like any other downloaded app.

Or build it yourself:

```sh
git clone https://github.com/mkemalgokce/watcher.git
cd watcher
tools/build-app.sh            # writes build/Watcher.app, signed ad hoc for this Mac
```

## Getting started

1. Open Watcher. The welcome sheet walks through trusting the root certificate; it is also under Tools ▸ Certificates.
2. Press **Record** (⌘E). Watcher listens on `127.0.0.1:9090`, and with the system proxy on (⇧⌘Y) it captures the whole Mac.
3. To capture a phone, open **Set Up a Device** (⇧⌘D) and follow the steps for iPhone, iPad, a Simulator or Android.
4. Press **Pause** to stop the proxy; your original network settings come back.

## Command line

```sh
swift run watcher-cli cert                       # path of the root certificate; trust it in Keychain Access
swift run watcher-cli start --har session.har    # capture to a HAR file
swift run watcher-cli tool block-list on
swift run watcher-cli rules export rules.json    # also: rules import, rules import-charles
swift run watcher-cli install-simulator-cert --device booted
swift run watcher-cli android cert               # also: android list | proxy --port 9090 | unproxy
swift run watcher-cli mcp                        # MCP server on stdin/stdout
curl -x http://127.0.0.1:9090 --cacert ~/.watcher/watcher-ca.pem https://example.com/
```

Settings live in `~/.watcher/settings.json` (mode 600, as it can hold proxy credentials) and are shared by the app and the CLI;
a running Watcher picks up edits within a second. `WATCHER_HOME=<dir>` points the CLI at another folder.

## Scripting

```js
async function onRequest(context, url, request) {   // request: method, headers, queries, body
  request.headers["X-Watcher"] = "1";
  return request;
}
async function onResponse(context, url, request, response) {   // response: statusCode, headers, body, bodyFilePath
  response.statusCode = 200;
  return response;
}
```

Scripts time out after 10 s.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| ⌘E · ⇧⌘Y | record / pause (starts and stops the proxy) · system proxy |
| ⌘N · ⌘O · ⌘S · ⇧⌘E | new request · open · save session · export HAR |
| ⌘K · ⌘⌫ | clear session (with undo) · delete request |
| ⌘R · ⌥⌘R · ⌘D | repeat · edit and repeat · star |
| ⇧⌘C · ⌥⌘C · ⇧⌘B | copy cURL · copy URL · set compare base |
| ⌘B · ⌘T · ⇧⌘D · ⇧⌘U | breakpoints · tools · device setup · converter |
| ⌘F · ⇧⌘L | filter · clear filters |
| ⌘1–4 | All / Starred / Errors / WebSocket |
| ⌥⌘N | new request from the cURL command on the clipboard |
| ⌘/ | every shortcut and the colour legend |

## Limits

Bodies a tool must read (scripting, breakpoints, GraphQL matching, throttling) are buffered up to 64 MB; streamed bodies keep
their first 1 MB; a WebSocket keeps its newest 2000 messages. Clients speak HTTP/1.1 to the proxy. Binary Charles sessions
(`.chls`, `.chlz`) need Charles installed. Installing the profile on a physical iPhone needs taps on the phone.

## Support

Watcher is free and open source, made by [Mustafa Kemal Gökçe](https://github.com/mkemalgokce). If it saves you time,
consider [sponsoring its development](https://github.com/sponsors/mkemalgokce). Bugs and ideas go to
[issues](https://github.com/mkemalgokce/watcher/issues/new/choose).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md); report security problems privately as described in [SECURITY.md](SECURITY.md).

```sh
make bootstrap   # once: tools from Brewfile and Mintfile, git hooks
make test        # every test; make test-unit skips the Accessibility-driven interaction tests
make lint        # also: make format, make format-check, make coverage
```

| Path | Contents |
| --- | --- |
| `Sources/WatcherCore` | proxy (SwiftNIO), TLS, rules and tools, scripting, settings, export; the engine both front ends use |
| `Sources/WatcherUI` | SwiftUI views and view models; every screen has a `#Preview` |
| `Sources/Watcher` | the app entry point |
| `Sources/watcher-cli` | the command line tool |
| `Sources/TreeSitterScanners` | external scanners of tree-sitter-css and -javascript 0.25.0, which their packages skip as dependencies |

Commits and pull request titles follow [Conventional Commits](https://www.conventionalcommits.org).

Changes reach `main` only through pull requests reviewed by the maintainer.

### Releasing

A maintainer pushes a `v*` tag (`git tag v1.0.0 && git push origin v1.0.0`). `.github/workflows/release.yml` waits for the
maintainer to approve the `release` environment, which alone holds the signing secrets; then it builds `Watcher-<version>.dmg`,
signs it with the Developer ID, notarizes and staples it, and publishes the release with notes from git-cliff. `make dmg`
builds the same DMG locally, signed ad hoc and not notarized.

## License

[MIT](LICENSE)
