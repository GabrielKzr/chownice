# Experimento físico ICE/QUIC

O script `run-physical-ice.sh` executa dois peers em redes distintas, estabelece
um caminho ICE direto e transporta dados de uma aplicação TCP por QUIC. O peer A
inicia uma transferência de 16384 bytes; o peer B executa um serviço TCP de echo.
O teste usa caminho direto e não verifica fallback automático para TURN.

## Preparação

Em ambas as máquinas, compile o projeto e o executável `test_quic_ice` com o
preset `all` (veja as [dependências de build](../../docs/build-dependencies.md)):

```sh
cmake --preset all
cmake --build --preset all -j 2
```

O script exige Linux, `sudo`, Python 3, `ip`, `flock`, `timeout`, `tcpdump`,
`nsenter` e `ss`. Cada interface de peer deve estar configurada com exatamente
um endereço IPv4 global e ter rotas na tabela principal até o servidor.

Os dois peers precisam acessar o mesmo servidor de sinalização e STUN. Se o IPv4
informado pertencer à própria máquina, o script inicia os serviços locais de
sinalização e coturn; nesse caso, o servidor deve usar outra interface, distinta
da interface do peer e de loopback. As portas TCP 5555 e UDP 3478 devem estar
livres. Se o servidor for remoto, os serviços devem estar ativos nele antes da
execução.

## Execução

Execute os comandos a partir da raiz do repositório, substituindo as interfaces
e usando o mesmo IPv4 do servidor nos dois peers. Inicie A e, em seguida, B:

```sh
# Na máquina do peer A
sudo bash sim/physical/run-physical-ice.sh a <interface-do-peer-a> <ipv4-do-servidor>

# Na máquina do peer B
sudo bash sim/physical/run-physical-ice.sh b <interface-do-peer-b> <ipv4-do-servidor>
```

Quando o servidor é local ao peer A, o script aguarda a conexão de B por até
120 segundos. O script move temporariamente a interface escolhida para um
network namespace e tenta restaurar sua configuração ao terminar.

Para interromper uma execução ou retomar a restauração da interface, use na
máquina afetada os mesmos parâmetros de interface e servidor:

```sh
sudo bash sim/physical/run-physical-ice.sh stop <interface> <ipv4-do-servidor>
sudo bash sim/physical/run-physical-ice.sh cleanup <interface> <ipv4-do-servidor>
```

`stop` solicita o encerramento da execução ativa; `cleanup` tenta recuperar o
estado registrado da interface.

## Logs e capturas

Cada execução cria, na máquina do respectivo peer, um diretório
`build/all/sim/physical/artifacts/<a-ou-b>-<data-hora>-<identificador>/`. O caminho é
impresso ao final. Entre os arquivos estão:

- `peer-a-lan.pcap` ou `peer-b-lan.pcap`: captura na interface do peer.
- `server.pcap`: captura na interface do servidor, quando ele é local.
- `peer-a.log` ou `peer-b.log`: saída do executável QUIC/ICE.
- `probe.log` em A e `echo.log` em B: registros da aplicação TCP.
- `signaling.log` e `turn.log`: registros dos serviços quando iniciados localmente.

As capturas usam o filtro `udp or tcp port 5555` e podem conter tráfego UDP de
fundo. O script não valida automaticamente os PCAPs ao final; eles podem ser
abertos no Wireshark ou verificados com `tcpdump -r <arquivo.pcap>`.
