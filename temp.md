```text
O QUICv1 utiliza pacotes com \textit{long header} (\texttt{Initial}, \texttt{0-RTT}, \texttt{Handshake} e \texttt{Retry}) durante o estabelecimento e a retomada de conexões, enquanto os pacotes com \textit{short header} (\texttt{1-RTT}) transportam dados e controle a partir da disponibilização das chaves de aplicação. Há ainda o pacote \textit{Version Negotiation}, cujo formato independe da versão do protocolo e permite informar as versões suportadas pelo servidor \citep{rfc8999, rfc9000}. A Tabela~\ref{tab:quic_packet_types} resume a função de cada tipo.

\begin{table}[htbp]
    \centering
    \begin{tabular}{@{}p{0.24\textwidth}p{\dimexpr0.76\textwidth-2\tabcolsep\relax}@{}}
        \toprule
        \textbf{Tipo de pacote} & \textbf{Função} \\
        \midrule
        \texttt{Initial} & Transporta as primeiras mensagens do \textit{handshake} TLS. Os datagramas enviados pelo cliente que contêm esse tipo de pacote devem ter ao menos 1200 bytes. \\
        \texttt{Handshake} & Transporta as mensagens TLS que completam a negociação criptográfica após o \texttt{ServerHello}. \\
        \texttt{Retry} & Permite ao servidor solicitar a validação do endereço do cliente antes de prosseguir com o \textit{handshake}. \\
        \texttt{0-RTT} & Transporta dados antecipados do cliente na retomada de uma sessão anterior. Esse recurso não foi avaliado nos experimentos. \\
        \texttt{1-RTT} & Transporta dados de aplicação e informações de controle após a disponibilização das chaves de aplicação. \\
        \textit{Version Negotiation} & Informa as versões suportadas pelo servidor quando a versão proposta pelo cliente não é aceita. \\
        \bottomrule
    \end{tabular}
    \caption{Tipos de pacotes QUIC e suas funções. Fonte: elaborado com base em \citep{rfc8999, rfc9000, rfc9001}.}
    \label{tab:quic_packet_types}
\end{table}
```

```text
\subsubsection{Proteção de pacotes}
\label{sec:quic_packet_protection}

A proteção dos pacotes QUIC varia conforme a etapa da conexão e complementa a proteção de cabeçalho descrita na Seção~\ref{sec:quic_header_protection}. O protocolo utiliza chaves distintas para os níveis \textit{Initial}, \textit{0-RTT}, \textit{Handshake} e \textit{1-RTT}, cujas garantias e limitações são resumidas a seguir \citep{rfc9001}.

Nos pacotes \texttt{Initial}, as chaves derivam de informações públicas, de modo que sua proteção não oferece confidencialidade contra observadores do tráfego. Os pacotes \texttt{Handshake} e \texttt{1-RTT} utilizam chaves derivadas da negociação TLS~1.3 para proteger, respectivamente, as mensagens posteriores ao \texttt{ServerHello} e os dados e controles da conexão. Os pacotes \texttt{0-RTT} utilizam chaves associadas a uma sessão anterior, mas não oferecem sigilo futuro (\textit{forward secrecy}) e estão sujeitos à reprodução de mensagens (\textit{replay}), exigindo cuidados da aplicação. Já o pacote \texttt{Retry} não é cifrado e possui uma etiqueta de integridade calculada com parâmetros públicos, que não autentica o servidor; o pacote \textit{Version Negotiation} não possui proteção criptográfica. Os mecanismos de derivação de chaves e de proteção são definidos no RFC~9001 \citep{rfc9001}.
```

```text
\subsubsection{\textit{Frames} do QUIC}

Os \textit{frames} são as unidades de informação transportadas no conteúdo dos pacotes QUIC, e um mesmo pacote pode conter vários deles, com funções de dados ou de controle \citep{rfc9000}. Entre os principais tipos, o \texttt{CRYPTO} transporta mensagens do \textit{handshake} TLS; o \texttt{STREAM}, dados das aplicações; e o \texttt{ACK}, confirmações de recebimento de pacotes. O \texttt{PING} solicita uma confirmação do receptor sem transportar dados de aplicação, enquanto o \texttt{CONNECTION\_\allowbreak{}CLOSE} sinaliza o encerramento da conexão. Os pacotes \texttt{Retry} e \textit{Version Negotiation} não transportam \textit{frames}. A especificação dos formatos e dos tipos permitidos em cada pacote é definida no RFC~9000 \citep{rfc9000}.
```

```text
\subsection{Retomada de sessão (0-RTT)}
\label{sec:0rtt_connection_recovery}

A retomada de sessão permite que o cliente utilize informações de uma conexão anterior com o mesmo servidor para enviar dados de aplicação antes de concluir um novo \textit{handshake}. A partir de uma chave pré-compartilhada (PSK), obtida por meio de um \textit{session ticket} do TLS~1.3, o cliente deriva as chaves 0-RTT e envia esses dados junto ao primeiro pacote \texttt{Initial}, sem aguardar uma resposta do servidor \citep{rfc9001}. O restante da negociação segue o fluxo 1-RTT. A Figura~\ref{fig:quic0rtt_vs_tcptls} compara a retomada de sessão no QUIC e no TCP com TLS.

\begin{figure}[!ht]
        \centering
        \includegraphics[width=0.8\linewidth]{fig/QUIC/quic0rtt_vs_tcptls_cmp.png}
        \caption{Comparação da retomada de sessão no QUIC (0-RTT) e no TCP com TLS. Fonte: adaptado de \citep{marx2020quic}.}
        \label{fig:quic0rtt_vs_tcptls}
\end{figure}

Os dados 0-RTT não oferecem sigilo futuro (\textit{forward secrecy}) e estão sujeitos à reprodução de mensagens (\textit{replay}), conforme discutido na Seção~\ref{sec:quic_packet_protection}. Por isso, a aplicação deve limitar os dados antecipados a operações que possam ser repetidas com segurança \citep{rfc9001}. Esse recurso não foi avaliado nos experimentos deste trabalho.
```

```text
\section{História do QUIC}

O desenvolvimento do QUIC foi motivado por limitações da pilha TCP/TLS/HTTP, como o bloqueio da entrega de todos os fluxos multiplexados sobre uma conexão TCP quando ocorre a perda de um segmento (\textit{Head-of-Line Blocking}). Além disso, a implementação do TCP no núcleo do sistema operacional e a interferência de equipamentos intermediários dificultam a implantação de alterações no protocolo. O QUIC utiliza UDP e implementa suas funções de transporte no espaço de usuário, facilitando sua evolução \citep{marx2020quic}.

A implementação original, denominada Google QUIC (GQUIC), foi desenvolvida pelo Google a partir de 2012 para melhorar o desempenho do tráfego HTTPS. Ela já integrava multiplexação de fluxos e mecanismos criptográficos, mas utilizava um protocolo de segurança próprio, o QUIC Crypto. Em 2016, o IETF criou o grupo de trabalho QUIC para padronizar o protocolo com base nessa experiência, incorporando alterações como a substituição do QUIC Crypto pelo TLS~1.3 e a separação entre o transporte e o mapeamento do HTTP \citep{marx2020quic}.

Esse processo resultou no QUICv1, publicado em 2021 no RFC~9000 e adotado como referência neste trabalho \citep{rfc9000}. A versão padronizada integra o estabelecimento do transporte ao \textit{handshake} TLS~1.3 e fornece \textit{streams} independentes em uma mesma conexão \citep{rfc9001}. A Figura~\ref{fig:quic_stack} apresenta a pilha resultante, na qual o QUIC incorpora funções anteriormente distribuídas entre TCP e TLS e serve de transporte para protocolos de aplicação, como o HTTP/3.

\begin{figure}[!ht]
    \centering
    \includegraphics[width=0.7\textwidth]{fig/QUIC/quic_stack.png}
    \caption{Pilha de protocolos utilizando QUIC. Fonte: adaptado de \citep{marx2020quic}.}
    \label{fig:quic_stack}
\end{figure}
```

## Modelos de Arquitetura de Rede — proposta de redação compacta

Substituir o trecho entre o início da seção e a subseção “WebRTC como referência arquitetural”. A proposta mantém as três figuras, as citações e as distinções conceituais; a subseção de WebRTC permanece como está.

```text
\section{Modelos de Arquitetura de Rede}
\label{sec:network_architecture_models}

A arquitetura de rede define como os participantes interagem e quais responsabilidades assumem na prestação de um serviço, enquanto a topologia descreve suas interconexões físicas ou lógicas. Assim, uma mesma arquitetura pode operar sobre diferentes topologias. Entre os modelos mais utilizados estão cliente-servidor e P2P, cujas fronteiras não são rígidas: componentes centralizados e distribuídos podem coexistir e assumir relevâncias distintas conforme a etapa da comunicação \citep{RFC5694}.

\subsection{Modelo Cliente-Servidor}

No modelo cliente-servidor, o servidor disponibiliza serviços ou recursos, enquanto o cliente fornece uma interface para requisitá-los. No modelo de acesso remoto (\textit{remote access model}) descrito por \citep{Tanenbaum2007}, o cliente solicita operações, e o servidor as executa e retorna os resultados, conforme a Figura~\ref{fig:tannenbaum_client_server}.

\begin{figure}[!ht]
        \centering
        \includegraphics[width=0.5\linewidth]{fig/NetworkModels/client_server.jpg}
        \caption{Diagrama de alto nível do modelo de acesso remoto cliente-servidor, baseado em \citep{Tanenbaum2007}.}
        \label{fig:tannenbaum_client_server}
\end{figure}

\subsection{Modelo Peer-to-Peer}
\label{sec:p2p_model}

Na arquitetura P2P, as responsabilidades são distribuídas entre os participantes, que podem atuar como provedores e consumidores de serviços, sem papéis fixos de cliente e servidor. Embora a literatura apresente diferentes definições, o RFC (\textit{Request for Comments}) 5694 \citep{RFC5694} caracteriza esses sistemas pelo compartilhamento de recursos para prover um serviço: os pares tanto fornecem quanto requisitam serviços e contribuem coletivamente para seu funcionamento. A associação histórica do P2P ao compartilhamento de conteúdo ilegal decorre de aplicações específicas, e não do modelo arquitetural.

Autores como \citep{Milojicic2002} contrapõem a centralização do modelo cliente-servidor à descentralização do P2P, como ilustra a Figura~\ref{fig:centralized_vs_p2p}. Essa distinção admite componentes centralizados em sistemas P2P, conforme a discussão do RFC~5694 apresentada no início desta seção.

\begin{figure}[!ht]
        \centering
        \includegraphics[width=0.6\linewidth]{fig/NetworkModels/centralized_vs_p2p.jpg}
        \caption{Diagrama de alto nível da comparação entre os modelos P2P e centralizado, baseado em \citep{Milojicic2002}.}
        \label{fig:centralized_vs_p2p}
\end{figure}

\subsection{Modelo Peer-to-Peer Híbrido}
\label{sec:hybrid_peer_to_peer_model}

Modelos P2P híbridos combinam comunicação entre pares com serviços centralizados de autenticação, descoberta, sinalização ou obtenção de metadados necessários à conexão \citep{Milojicic2002}. Na Figura~\ref{fig:hybrid_p2p}, o par A obtém informações de um servidor em (a) e as utiliza para estabelecer comunicação direta com B em (b).

\begin{figure}[!ht]
        \centering
        \includegraphics[width=0.6\linewidth]{fig/NetworkModels/hybrid_model.jpg}
        \caption{Exemplo de modelo híbrido, baseado em \citep{Milojicic2002}.}
        \label{fig:hybrid_p2p}
\end{figure}

O WebRTC, apresentado na Seção~\ref{sec:webrtc}, exemplifica essa organização: a sinalização e a coleta de candidatos ICE utilizam serviços auxiliares de sinalização, STUN e TURN, enquanto a troca de dados ocorre diretamente entre os pares sempre que possível.
```
