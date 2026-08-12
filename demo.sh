#!/usr/bin/env bash

DEMO_START=$(date +%s)

TEMP_DIR="upgrade-example"

# Java version configuration — sourced from .sdkmanrc
JAVA8_VERSION=$(grep '^java=8' "$(dirname "$0")/.sdkmanrc" | cut -d'=' -f2)
JAVA17_VERSION=$(grep '^java=17' "$(dirname "$0")/.sdkmanrc" | cut -d'=' -f2)
JAVA17_HOME="${SDKMAN_DIR:-$HOME/.sdkman}/candidates/java/$JAVA17_VERSION"

export SPRING_ADVISOR_MAPPING_CUSTOM_0_GIT_URI="https://github.com/dashaun-tanzu/advisor-mappings.git"
export SPRING_ADVISOR_MAPPING_CUSTOM_0_GIT_PATH="mappings/"
export SPRING_ADVISOR_MAPPING_CUSTOM_0_MERGE_STRATEGY=override

check_dependency() {
  local cmd=$1
  local install_msg=$2

  if ! command -v "$cmd" &> /dev/null; then
    echo "$cmd not found. $install_msg"
    return 1
  fi
  return 0
}

check_dependencies() {
  local missing_deps=()

  check_dependency "vendir" "Please install vendir first." || missing_deps+=("vendir")
  check_dependency "http" "Please install httpie first." || missing_deps+=("httpie")
  check_dependency "bc" "Please install bc first." || missing_deps+=("bc")
  check_dependency "git" "Please install git first." || missing_deps+=("git")
  check_dependency "jq" "Please install jq first." || missing_deps+=("jq")
  check_dependency "tar" "Please install tar first." || missing_deps+=("tar")
  check_dependency "trivy" "Please install trivy first (brew install trivy)." || missing_deps+=("trivy")

  if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "Missing dependencies: ${missing_deps[*]}"
    exit 1
  fi

  echo "All dependencies found."
}

check_env_vars() {
  local missing_vars=()

  [[ -z "${ADVISOR_VERSION}" ]] && missing_vars+=("ADVISOR_VERSION")

  if [ ${#missing_vars[@]} -gt 0 ]; then
    echo "Missing required environment variables: ${missing_vars[*]}"
    exit 1
  fi

  echo "All required environment variables found."
}

check_dependencies
check_env_vars

# Pre-warm the Trivy vulnerability DB once, before the demo starts, so the two
# in-demo scans run with --skip-db-update and avoid a live network pull.
echo "Pre-warming Trivy vulnerability database..."
trivy image --download-db-only --quiet

[[ ! -d "./vendir/demo-magic" ]] && vendir sync
. ./vendir/demo-magic/demo-magic.sh
export TYPE_SPEED=100
export DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"
export PROMPT_TIMEOUT=5


function cleanUp {
  # Stop leftovers from a previous run of THIS demo only, identified by main
  # class via jps. Unrelated JVMs on the machine are left alone — the app binds
  # a random port (SERVER_PORT=0), so nothing else here conflicts. The one thing
  # that does conflict is the fixed JMX port spring-boot:start uses to control
  # the app, which a stranded HelloSpringApplication would still be holding.
  if ! command -v jps &> /dev/null; then
    return 0
  fi

  local pids
  pids=$(jps | grep 'HelloSpringApplication' | cut -d ' ' -f 1)

  if [[ -n "$pids" ]]; then
    displayMessage "*** Stopping leftover HelloSpringApplication instances from a previous run..."
    for pid in $pids; do
      echo "*** Stopping PID $pid..."
      kill -9 "$pid" 2>/dev/null
    done
  fi
}

function talkingPoint() {
  wait
  clear
}

function initSDKman() {
  local sdkman_init
  sdkman_init="${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh"
  if [[ -f "$sdkman_init" ]]; then
    # shellcheck disable=SC1090
    source "$sdkman_init"
  else
    echo "SDKMAN not found. Please install SDKMAN first."
    exit 1
  fi
}

function init {
  rm -rf "$TEMP_DIR"
  mkdir "$TEMP_DIR"
  cd "$TEMP_DIR" || exit
  clear
}

function useJava8 {
  displayMessage "Use Java 8 for Spring Boot 2.6 baseline"
  pei "sdk use java $JAVA8_VERSION"
  pei "java -version"
}

function useJava17 {
  displayMessage "Switch to Java 17 for Spring Boot 4"
  pei "sdk use java $JAVA17_VERSION"
  pei "java -version"
}

function cloneApp {
  displayMessage "Clone a Spring Boot 2.6 application"
  pei "git clone --depth 1 https://github.com/dashaun/hello-spring-boot-2-6.git ./"
}

function springBootStart {
  # SERVER_PORT=0 makes Spring Boot bind any free port, so the demo never
  # collides with whatever else is running on the presenter's machine and does
  # not need to kill unrelated JVMs. The chosen port is recovered by appPort.
  displayMessage "Start the Spring Boot application on a random free port, Wait For It...."
  pei "SERVER_PORT=0 ./mvnw -q package spring-boot:start -Dfork=true -DskipTests 2>&1 | tee '$1' &"
}

function appPort {
  # Recover the port Spring Boot actually chose from the startup log. Boot 2.6
  # logs 'Tomcat started on port(s): NNNNN' and Boot 4.1 logs 'Tomcat started on
  # port NNNNN', so both spellings are matched.
  #
  # This doubles as the readiness gate for the run: talkingPoint's `wait` is
  # demo-magic's prompt (a few seconds), not the shell builtin, so nothing else
  # blocks on `mvn package` finishing. Waiting for the 'Started ... in N seconds'
  # line means the context is fully refreshed before validateApp calls actuator.
  # Default budget is 5 minutes to cover a cold build with dependency downloads.
  local log_file=$1
  local attempts=${2:-600}
  local port=""
  for ((i = 0; i < attempts; i++)); do
    if grep -qE 'Started .* in .* seconds' "$log_file" 2>/dev/null; then
      port=$(sed -nE 's/.*Tomcat started on port(\(s\))?:? ([0-9]+).*/\2/p' "$log_file" 2>/dev/null | tail -n1)
      if [[ -n "$port" ]]; then
        echo "$port"
        return 0
      fi
    fi
    sleep 0.5
  done
  return 1
}

function springBootStop {
  displayMessage "Stop the Spring Boot application"
  pei "./mvnw spring-boot:stop -Dspring-boot.stop.fork -Dfork=true"
}

function validateApp {
  local port=$1

  if [[ -z "$port" ]]; then
    echo "Could not determine the application port from the startup log"
    return 1
  fi

  displayMessage "Check application health on port $port"
  pei "http :$port/actuator/health 2>/dev/null"
}

function appPid {
  # Resolve the running app's JVM PID, retrying until it registers with jps.
  # spring-boot:start can return before the forked JVM is visible, which left
  # the PID empty when called immediately. Prints the PID, or nothing on timeout.
  local name=${1:-HelloSpringApplication}
  local attempts=${2:-60}
  local pid=""
  for ((i = 0; i < attempts; i++)); do
    pid=$(jps | grep "$name" | cut -d ' ' -f 1)
    if [[ -n "$pid" ]]; then
      echo "$pid"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

function showMemoryUsage {
  local pid=$1
  local log_file=$2

  if [[ -z "$pid" ]]; then
    echo "Could not find a running application process to measure"
    echo "0" >> "$log_file"
    return 1
  fi

  local rss
  rss=$(ps -o rss= "$pid" | tail -n1)
  if [[ -z "$rss" ]]; then
    echo "Could not read memory for PID ${pid}"
    echo "0" >> "$log_file"
    return 1
  fi

  local mem_usage
  mem_usage=$(bc <<< "scale=1; ${rss}/1024")
  echo "The process was using ${mem_usage} megabytes"
  echo "${mem_usage}" >> "$log_file"
}

function runCVECheck {
  local log_file=$1

  # Extract the CycloneDX SBOM that advisor wrote into build-config.json to a
  # standalone file for Trivy to scan.
  jq '.sbom' target/.advisor/build-config.json > sbom-cdx.json

  displayMessage "Scanning advisor's CycloneDX SBOM with Trivy..."
  pei "trivy sbom --skip-db-update --quiet --format json --scanners vuln sbom-cdx.json > trivy-report.json 2> trivy-check.log"
  local cve_count
  cve_count=$(jq '[.Results[]?.Vulnerabilities[]?] | length' trivy-report.json)
  echo "Found ${cve_count} known CVEs"
  echo "${cve_count}" > "$log_file"
}

function advisorArtifactId {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "$os" in
    Darwin)
      if [[ "$arch" == "arm64" ]]; then
        echo "application-advisor-cli-macos-arm64"
      else
        echo "application-advisor-cli-macos"
      fi
      ;;
    Linux)
      echo "application-advisor-cli-linux"
      ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
      echo "application-advisor-cli-windows"
      ;;
    *)
      echo "Unsupported OS: $os" >&2
      return 1
      ;;
  esac
}

function downloadAdvisor {
  local artifact tar_file
  artifact=$(advisorArtifactId) || exit 1
  tar_file="${HOME}/.m2/repository/com/vmware/tanzu/spring/${artifact}/${ADVISOR_VERSION}/${artifact}-${ADVISOR_VERSION}.tar"

  displayMessage "Download Spring Application Advisor CLI ${ADVISOR_VERSION} (${artifact})"
  pei "mvn -q dependency:get -Dartifact=com.vmware.tanzu.spring:${artifact}:${ADVISOR_VERSION}:tar -Dtransitive=false"
  pei "tar -xf '${tar_file}' -C ."
  pei "./cli-binary/advisor --version"
}

function advisorBuildConfig {
  displayMessage "Capture some metadata about the application with Advisor"
  pei "./cli-binary/advisor build-config get"
}

function captureSBOMCount {
  # Silently record the SBOM component count for the comparison table.
  # The count is shown to the audience in showBuildConfigSBOMint, not here.
  local log_file=$1
  cat target/.advisor/build-config.json | jq '.sbom.components | length' > "$log_file"
}

function showBuildConfigKeys {
  displayMessage "Some interesting information from that step:"
  pei "cat target/.advisor/build-config.json | jq 'keys'"
  echo "^^^ The top level elements in the build-config.json file"
}

function showBuildConfigGitMetadata {
  pei "cat target/.advisor/build-config.json | jq '.\"git-metadata\"'"
  echo "^^^ Information about the git repository"
}

function showBuildConfigSBOMint {
  displayMessage "Some interesting information from that step:"
  pei "cat target/.advisor/build-config.json | jq '.sbom.components | length'"
  echo "^^^ That's the number of components included in the SBOM"
}

function showBuildConfigSubmodules {
  pei "cat target/.advisor/build-config.json | jq '.submodules'"
  echo "^^^ The Maven coordinates (groupId:artifactId) of the artifact(s)"
}

function showBuildConfigTools {
  pei "cat target/.advisor/build-config.json | jq '.tools'"
  echo "^^^ The tools and versions being used"
}

function advisorUpgradePlanGet {
  displayMessage "How hard could it be to upgrade? Let's get a plan!"
  pei "./cli-binary/advisor upgrade-plan get"
}

function advisorUpgradePlanApplySquash {
  displayMessage "Do all the upgrades!"
  pei "./cli-binary/advisor upgrade-plan apply --squash 11"
  # Silently pin 4.1.0-RC1 (if SAA landed on the release candidate) to the GA 4.1.0.
  grep -rl --include='pom.xml' '4.1.0-RC1' . 2>/dev/null | while read -r f; do
    sed -i.bak 's/4\.1\.0-RC1/4.1.0/g' "$f" && rm -f "$f.bak"
  done
}

function advisorPatchApply {
  displayMessage "The upgrade left some CVEs behind. Patch every dependency to its latest patch version!"
  pei "./cli-binary/advisor patch apply"
}

function displayMessage() {
  echo "#### $1"
  echo ""
}

function startupTime() {
  echo "$(sed -nE 's/.* in ([0-9]+\.[0-9]+) seconds.*/\1/p' < $1)"
}

function statsSoFarTableColored {
  displayMessage "Comparison of memory usage, startup times, CVEs, and dependencies"
  echo ""

  local WHITE='\033[1;37m'
  local GREEN='\033[1;32m'
  local CYAN='\033[1;36m'
  local BLUE='\033[1;34m'
  local NC='\033[0m'

  printf "${WHITE}%-38s %-25s %-10s %-10s %-15s %s${NC}\n" "Configuration" "Startup Time (seconds)" "Deps" "CVEs" "(MB) Used" "(MB) Savings"
  echo -e "${WHITE}-------------------------------------------------------------------------------------------------------------------${NC}"

  MEM1=$(cat java8with2.6.log2)
  START1=$(startupTime 'java8with2.6.log')
  CVE1=$(cat java8with2.6.cves)
  DEPS1=$(cat java8with2.6.deps)
  printf "${RED}%-38s %-25s %-10s %-10s %-15s %s${NC}\n" "Spring Boot 2.6 with Java 8" "$START1" "$DEPS1" "$CVE1" "$MEM1" "-"

  MEM2=$(cat java17with4.0.log2)
  PERC2=$([ -n "$MEM2" ] && [ -n "$MEM1" ] && bc <<< "scale=2; 100 - ${MEM2}/${MEM1}*100" || echo "N/A")
  START2=$(startupTime 'java17with4.0.log')
  PERCSTART2=$([ -n "$START2" ] && [ -n "$START1" ] && bc <<< "scale=2; 100 - ${START2}/${START1}*100" || echo "N/A")
  CVE2=$(cat java17with4.0.cves)
  DEPS2=$(cat java17with4.0.deps)
  printf "${GREEN}%-38s %-25s %-10s %-10s %-15s %s ${NC}\n" "Spring Boot 4.1 with Java 17" "$START2 ($PERCSTART2% faster)" "$DEPS2" "$CVE2" "$MEM2" "$PERC2%"

  # The patched row only exists on the second printing of this table, after
  # `advisor patch apply` has run and its measurements have been collected.
  if [[ -f java17patched.cves ]]; then
    MEM3=$(cat java17patched.log2)
    PERC3=$([ -n "$MEM3" ] && [ -n "$MEM1" ] && bc <<< "scale=2; 100 - ${MEM3}/${MEM1}*100" || echo "N/A")
    START3=$(startupTime 'java17patched.log')
    PERCSTART3=$([ -n "$START3" ] && [ -n "$START1" ] && bc <<< "scale=2; 100 - ${START3}/${START1}*100" || echo "N/A")
    CVE3=$(cat java17patched.cves)
    DEPS3=$(cat java17patched.deps)
    printf "${CYAN}%-38s %-25s %-10s %-10s %-15s %s ${NC}\n" "Spring Boot 4.1 patched with Java 17" "$START3 ($PERCSTART3% faster)" "$DEPS3" "$CVE3" "$MEM3" "$PERC3%"
  fi

  echo -e "${WHITE}-------------------------------------------------------------------------------------------------------------------${NC}"
  DEMO_STOP=$(date +%s)
  DEMO_ELAPSED=$((DEMO_STOP - DEMO_START))
  echo ""
  echo ""
  echo -e "${BLUE}Demo elapsed time: ${DEMO_ELAPSED} seconds${NC}"
}

# Main execution flow

cleanUp
initSDKman
init
useJava8
talkingPoint
cloneApp
talkingPoint
downloadAdvisor
talkingPoint
advisorBuildConfig
talkingPoint
captureSBOMCount java8with2.6.deps
showBuildConfigKeys
talkingPoint
showBuildConfigGitMetadata
talkingPoint
showBuildConfigSBOMint
talkingPoint
showBuildConfigSubmodules
talkingPoint
showBuildConfigTools
talkingPoint
runCVECheck java8with2.6.cves
talkingPoint
springBootStart java8with2.6.log
talkingPoint
validateApp "$(appPort java8with2.6.log)"
talkingPoint
showMemoryUsage "$(appPid)" java8with2.6.log2
talkingPoint
springBootStop
talkingPoint
advisorUpgradePlanGet
talkingPoint
useJava17
talkingPoint
advisorUpgradePlanApplySquash
talkingPoint
advisorBuildConfig
talkingPoint
captureSBOMCount java17with4.0.deps
runCVECheck java17with4.0.cves
talkingPoint
springBootStart java17with4.0.log
talkingPoint
validateApp "$(appPort java17with4.0.log)"
talkingPoint
showMemoryUsage "$(appPid)" java17with4.0.log2
talkingPoint
springBootStop
talkingPoint
statsSoFarTableColored
talkingPoint
advisorPatchApply
talkingPoint
advisorBuildConfig
talkingPoint
captureSBOMCount java17patched.deps
runCVECheck java17patched.cves
talkingPoint
springBootStart java17patched.log
talkingPoint
validateApp "$(appPort java17patched.log)"
talkingPoint
showMemoryUsage "$(appPid)" java17patched.log2
talkingPoint
springBootStop
talkingPoint
statsSoFarTableColored
