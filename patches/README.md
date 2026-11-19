# Patches de dependências

Este diretório contém correções aplicadas às dependências compiladas pelo projeto.
O CMake aplica os patches automaticamente durante a preparação do build; não é
necessário modificar as bibliotecas instaladas no sistema.

- [libnice](libnice/README.md): corrige a remoção de uma allocation TURN quando
  o servidor responde `438 Stale nonce`. O patch repete uma vez o pedido de
  liberação com o novo nonce.
- [coturn](coturn/README.md): ajusta o `configure` para respeitar `TMPDIR`,
  permitindo que a preparação da dependência use um diretório dentro do build.

Os READMEs de cada patch descrevem a versão da dependência, os detalhes da
aplicação e as verificações disponíveis. As dependências gerenciadas ficam em
`build/<preset>/_deps/`; consulte também as
[instruções de build](../docs/build-dependencies.md).
