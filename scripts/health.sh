#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# mentoraix-workspace health check
# Checks each service port for a responsive HTTP status
# ============================================================

check_port() {
  local name="$1" port="$2" url="$3"
  if curl -sf -o /dev/null -m 3 "$url" 2>/dev/null; then
    printf "%-20s %-8s \033[1;32m✓ Running\033[0m\n" "$name" "$port"
  else
    printf "%-20s %-8s \033[1;31m✗ Down\033[0m\n" "$name" "$port"
  fi
}

echo "========================================="
echo " Service Health Check"
echo "========================================="
echo ""

check_port "SmartAIMentor" "58888" "http://localhost:58888/docs"
check_port "RecSys"        "8000"  "http://localhost:8000"
check_port "ClawCore"      "8001"  "http://localhost:8001/health"
check_port "mentoraixs"     "3000"  "http://localhost:3000"

echo ""
echo "========================================="
