#!/usr/bin/env bash
# Benchmark fpWeb puro x Zenith. Uso: bench/run.sh [saida_dir]
# Requisitos: fpc, ab (ApacheBench), curl. Executa tudo em localhost.
# Variáveis: ROUNDS (3), REQS (requisições por instância ab, 5000),
#            PROCS (instâncias ab paralelas, 4), CONC (concorrência por ab, 16)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-${TMPDIR:-/tmp}/zenith-bench}"
ROUNDS="${ROUNDS:-3}"; REQS="${REQS:-5000}"; PROCS="${PROCS:-4}"; CONC="${CONC:-16}"
mkdir -p "$OUT/fu" "$OUT/zu"

echo "[build] fpWeb (somente units do FPC)"
fpc -O2 -MObjFPC -Sh -FE"$OUT" -FU"$OUT/fu" "$ROOT/bench/fpweb/fpweb_bench.lpr" >/dev/null
echo "[build] Zenith"
fpc -O2 -MObjFPC -Sh -Fu"$ROOT/src" -Fu"$ROOT/src/deltamodel/src" \
    -Fu"$ROOT/src/deltamodel/src/orm" -Fu"$ROOT/src/deltamodel/src/orm/dialects" -Fu"$ROOT/src/deltamodel/src/orm/drivers" \
    -Fu"$ROOT/src/swagger4laz" \
    -Fu"$ROOT/bench/zenith" -FE"$OUT" -FU"$OUT/zu" "$ROOT/bench/zenith/zenith_bench.lpr" >/dev/null

echo '{"id":1,"name":"Item 1","price":1.5,"active":true}' > "$OUT/echo.json"
RESULTS="$OUT/results.csv"
echo "server,endpoint,round,rps,mean_ms,p50_ms,p99_ms,failed,cpu_ms_per_1k,rss_kb,hwm_kb,threads" > "$RESULTS"

proc_cpu_ms() { # utime+stime em ms
  awk -v hz="$(getconf CLK_TCK)" '{print ($14+$15)*1000/hz}' "/proc/$1/stat"; }
proc_kv() { awk -v k="$2:" '$1==k{print $2}' "/proc/$1/status"; }

run_server() { # nome binario porta
  local name=$1 bin=$2 port=$3
  if curl -s -o /dev/null "http://127.0.0.1:$port/"; then
    echo "porta $port já está em uso; encerre o processo antes do benchmark" >&2; exit 1
  fi
  BENCH_PORT=$port ZENITH_LOGFILE= "$OUT/$bin" >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 50); do curl -sf "http://127.0.0.1:$port/plaintext" >/dev/null && break; sleep 0.1; done
  echo "$name idle_rss_kb=$(proc_kv $pid VmRSS) threads=$(proc_kv $pid Threads)" >> "$OUT/idle.txt"
  for ep in plaintext json items echo; do
    local url="http://127.0.0.1:$port/$ep" extra=()
    [[ $ep == echo ]] && extra=(-p "$OUT/echo.json" -T application/json)
    ab -q -n 500 -c 8 "${extra[@]}" "$url" >/dev/null 2>&1 || true   # aquecimento
    for r in $(seq "$ROUNDS"); do
      local c0; c0=$(proc_cpu_ms $pid)
      local pids=()
      for i in $(seq "$PROCS"); do
        ab -q -n "$REQS" -c "$CONC" "${extra[@]}" "$url" > "$OUT/ab_${name}_${ep}_${r}_$i.txt" 2>&1 &
        pids+=($!)
      done
      wait "${pids[@]}" || true
      local c1; c1=$(proc_cpu_ms $pid)
      local total=$((REQS*PROCS))
      local agg; agg=$(cat "$OUT"/ab_${name}_${ep}_${r}_*.txt | awk '
        /^Requests per second/ {rps+=$4}
        /^Time per request.*\(mean\)$/ {mean+=$4; n++}
        /^Failed requests/ {fail+=$3}
        /^  50%/ {if ($2>p50) p50=$2}
        /^  99%/ {if ($2>p99) p99=$2}
        END {if (n==0) {print "0,0,0,0,-1"; exit} printf "%.0f,%.2f,%d,%d,%d", rps, mean/n, p50, p99, fail}')
      IFS=, read -r rps mean p50 p99 fail <<< "$agg"
      local cpu; cpu=$(awk -v a="$c0" -v b="$c1" -v t="$total" 'BEGIN{printf "%.1f",(b-a)*1000/t}')
      echo "$name,$ep,$r,$rps,$mean,$p50,$p99,$fail,$cpu,$(proc_kv $pid VmRSS),$(proc_kv $pid VmHWM),$(proc_kv $pid Threads)" >> "$RESULTS"
      echo "  $name $ep r$r: ${rps} req/s p99=${p99}ms falhas=$fail cpu/1k=${cpu}ms"
      sleep 2
    done
  done
  kill $pid; wait $pid 2>/dev/null || true
}

: > "$OUT/idle.txt"
run_server fpweb fpweb_bench 9001
run_server zenith zenith_bench 9002
echo "[ok] resultados em $RESULTS"
