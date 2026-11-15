#!/usr/bin/env bash
# Experimento físico QUIC/ICE direto com configuração derivada da interface.
# Uso: sudo bash sim/physical/run-physical-ice.sh <a|b|cleanup|stop> <interface> <IPv4-servidor>
# Rede IPv4 pré-configurada, com um endereço global na interface e rotas na tabela main.
# Servidor local: serviços iniciados em outra interface; remoto: serviços já ativos.
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_dir"
artifact_root="$repo_dir/sim/physical/artifacts"
role=${1:-}
interface=${2:-}
server_ip=${3:-}
if (( $# != 3 )) || [[ ! $role =~ ^(a|b|cleanup|stop)$ ]] ||
   [[ ! $interface =~ ^[a-zA-Z0-9_.:-]+$ || $interface == lo ]]; then
    echo "Uso: sudo bash sim/physical/run-physical-ice.sh <a|b|cleanup|stop> <interface> <IPv4-servidor>" >&2
    exit 1
fi
python3 - "$server_ip" <<'PY'
import ipaddress
import sys
ipaddress.IPv4Address(sys.argv[1])
PY
if (( EUID != 0 )); then
    echo "Execute com sudo." >&2
    exit 1
fi
for tool in ip python3 flock timeout; do
    command -v "$tool" >/dev/null || { echo "Ferramenta ausente: $tool" >&2; exit 1; }
done
state_file="/run/physical-ice-$interface.state"

stop_process() {
    [[ -n $1 ]] || return 0
    kill -KILL "$1" 2>/dev/null || true
}

# A configuração é lida como dados, sem executar conteúdo dos artefatos.
restore_network() {
    local saved_dir=$1 saved_namespace saved_interface saved_managed saved_host_namespace
    saved_namespace=$(cat "$saved_dir/namespace")
    saved_host_namespace="$saved_namespace-host"
    saved_interface=$(cat "$saved_dir/interface")
    if ip netns list | awk '{print $1}' | grep -Fxq "$saved_namespace"; then
        while read -r namespace_pid; do
            [[ -n $namespace_pid ]] && stop_process "$namespace_pid"
        done < <(ip netns pids "$saved_namespace")
        if ip -n "$saved_namespace" link show dev "$saved_interface" >/dev/null 2>&1; then
            ip -n "$saved_namespace" link set dev "$saved_interface" netns "$saved_host_namespace" || return 1
        fi
        ip netns del "$saved_namespace" || return 1
    fi
    ip link show dev "$saved_interface" >/dev/null || return 1
    ip link set dev "$saved_interface" up || return 1
    python3 - "$saved_dir" <<'PY' || return 1
import json
from pathlib import Path
import subprocess
import sys
p = Path(sys.argv[1])
interface = (p / 'interface').read_text().strip()
for address in json.loads((p / 'addresses.json').read_text())[0]['addr_info']:
    family = '-4' if address['family'] == 'inet' else '-6'
    cmd = ['ip', family, 'addr', 'replace', f"{address['local']}/{address['prefixlen']}", 'dev', interface]
    if address.get('broadcast'):
        cmd += ['broadcast', address['broadcast']]
    if address.get('scope'):
        cmd += ['scope', address['scope']]
    if address.get('label'):
        cmd += ['label', address['label']]
    subprocess.run(cmd, check=True)
PY
    local family route
    local -a route_args
    for family in 4 6; do
        while IFS= read -r route; do
            [[ -n $route ]] || continue
            read -r -a route_args <<< "$route"
            ip -"$family" route replace "${route_args[@]}" || return 1
        done < "$saved_dir/routes-$family.txt"
    done
    if [[ $(cat "$saved_dir/link-up") == 0 ]]; then
        ip link set dev "$saved_interface" down || return 1
    fi
    if ip netns list | awk '{print $1}' | grep -Fxq "$saved_host_namespace"; then
        ip netns del "$saved_host_namespace" || return 1
    fi
    saved_managed=$(cat "$saved_dir/nm-managed")
    if [[ $saved_managed == yes ]]; then
        timeout 10s nmcli device set "$saved_interface" managed yes || return 1
    fi
}

if [[ $role == cleanup || $role == stop ]]; then
    [[ -f $state_file ]] || { echo "Nenhuma execução registrada para $interface."; exit 0; }
    saved_dir=$(cat "$state_file")
    if [[ $role == stop && -f $saved_dir/script-pid ]]; then
        saved_pid=$(cat "$saved_dir/script-pid")
        saved_command=$(tr '\0' ' ' <"/proc/$saved_pid/cmdline" 2>/dev/null || true)
        if [[ $saved_command == *run-physical-ice.sh* ]]; then
            kill -TERM "$saved_pid" 2>/dev/null || true
        fi
    fi
fi
# O lock é liberado automaticamente na saída; filhos fecham o descritor.
exec 9>"/run/lock/physical-ice-$interface.lock"
flock -w 15 9 || { echo "Execução ativa para $interface; use stop." >&2; exit 1; }
if [[ -f $state_file ]]; then
    saved_dir=$(cat "$state_file")
    for pid_file in "$saved_dir"/*.pid; do
        [[ -f $pid_file ]] || continue
        saved_pid=$(cat "$pid_file")
        # Só encerra auxiliares que continuam associados aos logs desta execução.
        saved_stdout=$(readlink -f "/proc/$saved_pid/fd/1" 2>/dev/null || true)
        [[ $saved_stdout == "$saved_dir/"* ]] && stop_process "$saved_pid"
    done
    restore_network "$saved_dir" || { echo "Recuperação incompleta; dados em $saved_dir" >&2; exit 1; }
    rm -f "$state_file"
fi
if [[ $role == cleanup || $role == stop ]]; then
    echo "Recuperação concluída para $interface."
    exit 0
fi

for tool in tcpdump nsenter ss; do
    command -v "$tool" >/dev/null || { echo "Ferramenta ausente: $tool" >&2; exit 1; }
done
peer_bin="$repo_dir/build/all/source/tests/test_quic_ice"
[[ -x $peer_bin ]] || { echo "Compile o target test_quic_ice no preset all." >&2; exit 1; }
ip link show dev "$interface" >/dev/null
interface_json=$(ip -j -4 addr show dev "$interface")
peer_ip=$(python3 -c '
import json, sys
addresses = [a["local"] for a in json.load(sys.stdin)[0]["addr_info"] if a["scope"] == "global"]
if len(addresses) != 1:
    sys.exit("A interface precisa ter exatamente um IPv4 global para identificar o peer sem ambiguidade.")
print(addresses[0])
' <<< "$interface_json")
server_interface=$(ip -j -4 addr show | python3 -c '
import json, sys
server = sys.argv[1]
print(next((i["ifname"] for i in json.load(sys.stdin) if any(a["local"] == server for a in i["addr_info"])), ""))
' "$server_ip")
if [[ $server_interface == "$interface" || $server_interface == lo ]]; then
    echo "O servidor local precisa estar em outra interface, fora da LAN isolada do peer." >&2
    exit 1
fi
turn_bin="$repo_dir/build/all/_deps/coturn-4.6.3/install/bin/turnserver"
if [[ -n $server_interface ]]; then
    [[ -x $turn_bin ]] || { echo "Binário coturn ausente: $turn_bin" >&2; exit 1; }
    [[ -z $(ss -H -ltn '( sport = :5555 )') && -z $(ss -H -lun '( sport = :3478 )') ]] || {
        echo "Porta 5555 ou 3478 ocupada; encerre o serviço anterior." >&2; exit 1;
    }
fi
namespace="physical-peer-$role"
if ip netns list | awk '{print $1}' | grep -Eq "^($namespace|$namespace-host)$"; then
    echo "Namespace $namespace já existe sem recuperação registrada para esta interface." >&2
    exit 1
fi
mkdir -p "$artifact_root"
log_dir=$(mktemp -d "$artifact_root/$role-$(date +%Y%m%d-%H%M%S)-XXXXXX")
printf '%s\n' "$interface" > "$log_dir/interface"
printf '%s\n' "$namespace" > "$log_dir/namespace"
printf '%s\n' "$$" > "$log_dir/script-pid"
ip -j addr show dev "$interface" > "$log_dir/addresses.json"
ip -j link show dev "$interface" | python3 -c 'import json,sys; print(int("UP" in json.load(sys.stdin)[0]["flags"]))' > "$log_dir/link-up"
ip -4 route show table main dev "$interface" > "$log_dir/routes-4.txt"
ip -6 route show table main dev "$interface" > "$log_dir/routes-6.txt"
nm_managed=no
if command -v nmcli >/dev/null; then
    nm_managed=$(nmcli -g GENERAL.NM-MANAGED device show "$interface" 2>/dev/null || echo no)
fi
printf '%s\n' "$nm_managed" > "$log_dir/nm-managed"
printf '%s\n' "$log_dir" > "$state_file"
pids=()
# Invocada pelo trap EXIT.
# shellcheck disable=SC2317
cleanup() {
    local status=$?
    set +e
    trap - EXIT
    trap '' HUP INT TERM
    sleep 1
    for pid in "${pids[@]}"; do stop_process "$pid"; done
    if restore_network "$log_dir"; then
        rm -f "$state_file"
        echo "Limpeza concluída."
    else
        echo "Restauração incompleta. Execute cleanup com os mesmos parâmetros; dados em $log_dir." >&2
        status=1
    fi
    if [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]]; then
        chown -R "$SUDO_UID:$SUDO_GID" "$log_dir"
    fi
    echo "Logs e PCAPs em $log_dir"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ $nm_managed == yes ]]; then nmcli device set "$interface" managed no; fi
ip netns attach "$namespace-host" "$$"
ip netns add "$namespace"
ip link set dev "$interface" netns "$namespace"
ip -n "$namespace" link set lo up
ip -n "$namespace" link set dev "$interface" up
# O mesmo snapshot usado na restauração fornece os endereços IPv4 do peer.
python3 - "$log_dir/addresses.json" "$namespace" "$interface" <<'PY'
import json
import subprocess
import sys
for a in json.load(open(sys.argv[1]))[0]['addr_info']:
    if a['family'] == 'inet':
        subprocess.run(['ip', '-n', sys.argv[2], 'addr', 'replace',
                        f"{a['local']}/{a['prefixlen']}", 'dev', sys.argv[3]], check=True)
PY
while IFS= read -r route; do
    [[ -n $route ]] || continue
    read -r -a route_args <<< "$route"
    ip -n "$namespace" -4 route replace "${route_args[@]}"
done < "$log_dir/routes-4.txt"
ip -n "$namespace" route get "$server_ip" | tee "$log_dir/route.txt"

nsenter --net="/var/run/netns/$namespace" -- tcpdump -i "$interface" -nn -s 0 -U -Z root \
    -w "$log_dir/peer-$role-lan.pcap" 'udp or tcp port 5555' >"$log_dir/peer-$role-tcpdump.log" 2>&1 9>&- &
pids+=("$!")
printf '%s\n' "$!" > "$log_dir/capture.pid"
sleep 0.2
kill -0 "${pids[-1]}" || { echo "Falha ao iniciar captura." >&2; exit 1; }
if [[ -n $server_interface ]]; then
    tcpdump -i "$server_interface" -nn -s 0 -U -Z root \
        -w "$log_dir/server.pcap" 'udp or tcp port 5555' >"$log_dir/server-tcpdump.log" 2>&1 9>&- &
    pids+=("$!"); printf '%s\n' "$!" > "$log_dir/server-capture.pid"
    sleep 0.2
    kill -0 "${pids[-1]}" || { echo "Falha na captura do servidor." >&2; exit 1; }
    "$turn_bin" -n --listening-ip="$server_ip" --listening-ip=127.0.0.1 \
        --relay-ip="$server_ip" --listening-port=3478 --min-port=49160 --max-port=49200 \
        --lt-cred-mech --realm=ice-test --user=ice-test:ice-test-password \
        --no-tcp --no-tls --no-dtls --no-cli --log-file=stdout --pidfile=/dev/null \
        >"$log_dir/turn.log" 2>&1 9>&- &
    pids+=("$!"); printf '%s\n' "$!" > "$log_dir/turn.pid"
    python3 -u source/tests/nice/test_ice_udp_transport/signaling.py \
        >"$log_dir/signaling.log" 2>&1 9>&- &
    pids+=("$!"); printf '%s\n' "$!" > "$log_dir/signaling.pid"
    ready=0
    for _ in {1..50}; do
        if grep -q '^READY$' "$log_dir/signaling.log"; then ready=1; break; fi
        sleep 0.1
    done
    (( ready )) || { echo "Serviços não ficaram prontos; veja os logs." >&2; exit 1; }
fi

echo "Peer $role: $peer_ip em $interface; servidor $server_ip:5555."
if [[ $role == b ]]; then
    ip netns exec "$namespace" python3 -u - >"$log_dir/echo.log" 2>&1 9>&- <<'PY' &
import socket
with socket.socket() as listener:
    listener.bind(('127.0.0.1', 0))
    listener.listen()
    print(listener.getsockname()[1], flush=True)
    conn, _ = listener.accept()
    with conn:
        while data := conn.recv(8192):
            conn.sendall(data)
PY
    pids+=("$!"); printf '%s\n' "$!" > "$log_dir/echo.pid"
    for _ in {1..30}; do
        [[ -s $log_dir/echo.log ]] && break
        sleep 0.1
    done
    read -r local_tcp_port < "$log_dir/echo.log"
    [[ $local_tcp_port =~ ^[0-9]+$ ]] || { echo "Echo não ficou pronto." >&2; exit 1; }
    peer_mode=-s
else
    local_tcp_port=$(ip netns exec "$namespace" python3 -c \
        'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
    peer_mode=-c
    ip netns exec "$namespace" env LOCAL_TCP_PORT="$local_tcp_port" \
        python3 -u - >"$log_dir/probe.log" 2>&1 9>&- <<'PY' &
import socket
import time
import os

deadline = time.monotonic() + 120
while True:
    try:
        conn = socket.create_connection(("127.0.0.1", int(os.environ["LOCAL_TCP_PORT"])), timeout=1)
        break
    except OSError:
        if time.monotonic() >= deadline:
            raise
        time.sleep(0.05)
with conn:
    conn.settimeout(20)
    payload = bytes(n % 251 for n in range(16384))
    conn.sendall(payload)
    received = bytearray()
    while len(received) < len(payload):
        block = conn.recv(len(payload) - len(received))
        if not block:
            raise RuntimeError("EOF antecipado")
        received.extend(block)
    assert received == payload, "Dados diferentes"
    conn.shutdown(socket.SHUT_WR)
    assert conn.recv(1) == b"", "Dados extras"
print("OK: 16384 bytes íntegros e EOF", flush=True)
PY
    probe_pid=$!
    pids+=("$probe_pid"); printf '%s\n' "$probe_pid" > "$log_dir/probe.pid"
fi
printf '%s\n' "$local_tcp_port" > "$log_dir/local-tcp-port.txt"
# O servidor local em A aguarda B, como no experimento original.
if [[ $role == a && -n $server_interface ]]; then
    echo "Serviços prontos. Aguardando peer B por até 120 segundos..."
    connected=0
    for _ in {1..1200}; do
        if [[ -n $(ss -H -tn state established '( sport = :5555 )') ]]; then connected=1; break; fi
        sleep 0.1
    done
    (( connected )) || { echo "Peer B não conectou ao signaling." >&2; exit 1; }
fi
cd "$repo_dir/source"
ip netns exec "$namespace" env PATCHBAY_ISP_ADDRESS="$server_ip" PATCHBAY_LOCAL_ADDRESS="$peer_ip" \
    "$peer_bin" -d "$peer_mode" "$local_tcp_port" 127.0.0.1 \
    >"$log_dir/peer-$role.log" 2>&1 9>&- &
peer_pid=$!
pids+=("$peer_pid"); printf '%s\n' "$peer_pid" > "$log_dir/peer.pid"
set +e
wait "$peer_pid"
peer_status=$?
cat "$log_dir/peer-$role.log"
(( peer_status == 0 )) || exit "$peer_status"
if [[ $role == a ]]; then
    wait "$probe_pid"
    probe_status=$?
    cat "$log_dir/probe.log"
    exit "$probe_status"
fi
exit 0
