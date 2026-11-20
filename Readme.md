# chownice

Protótipo de pesquisa para comunicação ponto a ponto entre aplicações TCP em
redes distintas, incluindo cenários com NAT. O projeto integra ICE, por meio
da libnice, e QUIC, por meio da OpenSSL, para estabelecer conectividade e
transportar dados entre os peers. A arquitetura do WebRTC serve como referência
para a separação das etapas de sinalização, conectividade e transporte.

O ICE pode selecionar um caminho direto ou utilizar retransmissão TURN. Um
servidor de sinalização e serviços STUN/TURN auxiliam o estabelecimento da
comunicação. As aplicações mantêm conexões TCP locais; seus dados são
transportados entre os peers pelo QUIC. O projeto também conserva a
implementação de CHOWNAT e testes de tunelamento TCP sobre UDP.

O transporte QUIC utilizado nos testes é o da OpenSSL. `quic_like` é um esboço
de implementação própria, não um transporte completo. O protótipo não
implementa a pilha WebRTC nem uma API de DataChannel.

## Estrutura do repositório

- `source/`: bibliotecas C, implementações dos transportes e testes.
- `sim/patchbay/`: testes automatizados de rede em namespaces Linux.
- `sim/physical/`: experimento físico ICE/QUIC e documentação de execução.
- `sim/gns3/`: configurações e referências para laboratório GNS3.
- `cmake_modules/`: configuração de dependências e testes do CMake.
- `patches/`: correções aplicadas às dependências gerenciadas.
- `docs/text/`: fontes LaTeX, imagens e bibliografia do TCC.

## Build e testes

Em Linux, configure e compile o projeto com o preset `all`, depois execute os
testes registrados:

```sh
cmake --preset all
cmake --build --preset all -j2
ctest --preset all
```

O preset usa `build/all/` e inclui os testes de rede com Patchbay. Para saída
detalhada, use `ctest --preset all -V`. O CTest não recompila os executáveis.
O teste de sessão prolongada é separado, no preset `long`; veja as
[instruções do teste](source/tests/long/README.md).

O build gerencia OpenSSL, libnice, coturn e outras dependências em `_deps`;
compiladores, ferramentas Linux, GLib e Rust/Cargo estão entre os requisitos
externos. Consulte [dependências do build](docs/build-dependencies.md) para a
lista completa e [patches](patches/README.md) para as correções aplicadas.

## PDF da tese

Para gerar o PDF, instale o [Tectonic](https://tectonic-typesetting.github.io/).
Ele pode baixar os arquivos LaTeX necessários na primeira execução.

```sh
cmake --preset thesis
cmake --build --preset thesis
```

O PDF é gerado em `build/thesis/main.pdf`. O alvo copia os fontes para o
diretório de build e não escreve arquivos gerados em `docs/text/`.

## Testes de rede e capturas

O [Patchbay](sim/patchbay/README.md) cria peers e roteadores em namespaces Linux
para executar os cenários de rede. Para habilitar a captura de pacotes:

```sh
PATCHBAY_PCAP=1 ctest --preset all
```

Os PCAPs ficam em
`build/all/sim/patchbay/artifacts/<teste>/pcap/<nó>/`. A captura requer um
tcpdump compatível; consulte o README do Patchbay para requisitos e opções.

## Experimento físico

O experimento físico executa dois peers em redes distintas e testa a transferência
TCP pelo caminho ICE direto com QUIC. Após compilar com o preset `all`, execute
em cada máquina, substituindo a interface e o IPv4 do servidor de sinalização/STUN:

```sh
# Peer A
sudo bash sim/physical/run-physical-ice.sh a <interface-do-peer-a> <ipv4-do-servidor>

# Peer B
sudo bash sim/physical/run-physical-ice.sh b <interface-do-peer-b> <ipv4-do-servidor>
```

Os logs e PCAPs ficam em `build/all/sim/physical/artifacts/` na máquina de cada
peer. Veja [sim/physical](sim/physical/README.md) para requisitos, ordem de
execução e recuperação da interface de rede.

## Escopo

A avaliação funcional cobre o estabelecimento da comunicação, a integridade dos
dados e a manutenção e liberação de recursos nas configurações testadas. Os
testes com TURN obrigatório verificam a retransmissão, sem demonstrar seleção
automática de TURN após falha de um caminho direto. O projeto permanece um
protótipo de pesquisa; os resultados não representam uma avaliação geral de
latência, vazão ou funcionamento em todos os tipos de NAT.
