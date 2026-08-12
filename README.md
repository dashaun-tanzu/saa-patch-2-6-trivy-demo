[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]

![Demo](demo.gif)

# Spring Application Advisor + Trivy Upgrade Example

## Description

This interactive demo showcases the power of Spring Application Advisor (SAA) by automatically upgrading a Spring Boot application from version 2.6 to 4.1, then applying patch-level upgrades to every dependency to clear the remaining CVEs. CVE counts are produced by scanning the advisor-generated CycloneDX SBOM with the [Trivy](https://github.com/aquasecurity/trivy) CLI.

### What the Demo Does

1. **Environment Setup**: Configures Java 8 and Java 17 environments using SDKMAN
2. **Baseline Measurement**: Clones and runs a Spring Boot 2.6 application with Java 8, measuring:
   - Startup time
   - Memory usage
   - Known CVEs (via `trivy sbom` against the CycloneDX SBOM that `advisor build-config get` produces)
3. **Application Analysis**: Uses Spring Application Advisor to analyze the existing application, capturing:
   - Build configuration metadata
   - Software Bill of Materials (SBOM) with component/dependency inventory
   - Git repository information
   - Tool versions
4. **Automated Upgrade**: Generates and applies an upgrade plan that transforms the application to Spring Boot 4.1
5. **Post-Upgrade Analysis**: Runs `advisor build-config get` again after the upgrade to capture the updated SBOM
6. **Performance Validation**: Runs the upgraded application with Java 17 and measures the same metrics
7. **First Results Comparison**: Displays the 2.6 vs 4.1 table — the major-version upgrade typically still leaves some CVEs behind
8. **Patch-Level Upgrade**: Runs `advisor patch apply`, which moves every dependency to its latest patch version in a single pass
9. **Post-Patch Analysis**: Runs `advisor build-config get` a third time for a fresh SBOM, rescans it with Trivy, and runs/measures the app again
10. **Final Results Comparison**: Reprints the table with a third row, showing the CVE count driven to zero:
    - Startup time (with % improvement)
    - Dependency count (from SBOM)
    - Known CVE count (from Trivy)
    - Memory usage
    - Memory savings (%)

### Key Benefits Demonstrated

- **Zero Manual Effort**: Complete upgrade from Spring Boot 2.6 → 4.1 with no manual code changes
- **Performance Gains**: Typically shows improvements in startup speed and memory efficiency
- **Security Posture**: Demonstrates CVE reduction achieved by upgrading to a modern, supported version
- **Finishing the Job**: The major-version upgrade alone leaves residual CVEs; `advisor patch apply` closes them out by taking every dependency to its latest patch release
- **Dependency Insight**: SBOM comparison shows how the dependency footprint changes after upgrade
- **Modern Java Features**: Leverages Java 17 optimizations and Spring Boot 4.x enhancements

## Prerequisites

- [Spring Application Advisor](https://enterprise.spring.io/spring-application-advisor)
  > Spring Enterprise Repository Access required
- [SDKMan](https://sdkman.io/install)
  > i.e. `curl -s "https://get.sdkman.io" | bash`
- [Trivy](https://github.com/aquasecurity/trivy)
  > i.e. `brew install trivy`
- [Httpie](https://httpie.io/) needs to be in the path
  > i.e. `brew install httpie`
- [jq](https://jqlang.github.io/jq/) needs to be in the path
  > i.e. `brew install jq`
- bc, pv, zip, unzip, gcc, zlib1g-dev
  > i.e. `sudo apt install bc pv zip unzip gcc zlib1g-dev -y`
- [Vendir](https://carvel.dev/vendir/)
  > i.e. `brew tap carvel-dev/carvel && brew install vendir`

## Required Environment Variables

```bash
export ADVISOR_VERSION=<advisor-cli-version>
```

- **ADVISOR_VERSION**: Version of the Spring Application Advisor CLI to download. This demo requires **1.6.7** or later for the `advisor patch apply` step (already set in `.envrc`).

Trivy uses its own bundled vulnerability database and does not require API keys or credentials.

## Quick Start

```bash
./demo.sh
```

## Recording the Demo

Generate `demo.cast` with asciinema:

```bash
asciinema rec demo.cast --overwrite --cols 200 --rows 50 -c ./demo.sh
```

> **Note:** when asciinema runs without a TTY it records in headless mode and **ignores `--cols`/`--rows`**, defaulting to 80x24. The results table is 115 characters wide, so it wraps and looks broken at that size. The terminal size lives in the cast's JSON header and only affects rendering, so you can fix it after the fact without re-running the demo:
>
> ```bash
> python3 - <<'EOF'
> import json
> lines = open('demo.cast').read().splitlines()
> h = json.loads(lines[0]); h["term"]["cols"] = 120; h["term"]["rows"] = 32
> lines[0] = json.dumps(h)
> open('demo.cast', 'w').write("\n".join(lines) + "\n")
> EOF
> ```

Convert to `demo.gif` with agg:

```bash
agg --speed 2 --no-loop demo.cast demo.gif
```

120x32 is the size used for the committed `demo.gif` — wide enough for the table with little dead space.

## Ports

The app is started with `SERVER_PORT=0`, so Spring Boot binds an arbitrary free port on each of the three runs and the demo reads the chosen port back out of the startup log. Nothing needs to be free on 8080, and — unlike some of the sibling demos — this one does **not** kill every `java` process on the host. It stops only leftover `HelloSpringApplication` JVMs from a previous run of this same demo.

## Attributions
- [Demo Magic](https://github.com/paxtonhare/demo-magic) is pulled via `vendir sync` (skipped if already present)
- [Trivy](https://github.com/aquasecurity/trivy) by Aqua Security

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[forks-shield]: https://img.shields.io/github/forks/dashaun-tanzu/saa-patch-2-6-trivy-demo.svg?style=for-the-badge
[forks-url]: https://github.com/dashaun-tanzu/saa-patch-2-6-trivy-demo/forks
[stars-shield]: https://img.shields.io/github/stars/dashaun-tanzu/saa-patch-2-6-trivy-demo.svg?style=for-the-badge
[stars-url]: https://github.com/dashaun-tanzu/saa-patch-2-6-trivy-demo/stargazers
[issues-shield]: https://img.shields.io/github/issues/dashaun-tanzu/saa-patch-2-6-trivy-demo.svg?style=for-the-badge
[issues-url]: https://github.com/dashaun-tanzu/saa-patch-2-6-trivy-demo/issues
