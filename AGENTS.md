# Orientações para agentes — Zenith

Projeto Free Pascal/Lazarus. Fontes principais em `src`, exemplos em `demo`.
`src/deltamodel` e `src/swagger4laz` são submódulos Git com histórico próprio.

- Inspecione o estado da raiz e do submódulo relevante antes de alterar arquivos.
  Preserve o trabalho local existente; não limpe binários ou mudanças do usuário.
- Mudanças de ORM, DDL e bancos pertencem a `src/deltamodel`. Leia as orientações
  em `src/deltamodel/AGENTS.md` e o README daquele projeto.
- Compile testes em diretório temporário com `-FE` e `-FU`, evitando sobrescrever
  artefatos rastreados. Não faça commits ou atualize ponteiros de submódulos sem pedido.
- Para integração com bancos, use os containers descartáveis de
  `src/deltamodel/tests/podman/run.sh`; documentação em
  `src/deltamodel/tests/podman/README.md`. Nunca aponte os testes para bases reais.
- Registre claramente testes executados, versões de servidores e limitações.
  Teste unitário de SQL gerado não equivale a integração com servidor real.
- Documentação de uso e instruções para agentes devem acompanhar mudanças de
  comportamento; use português, mantendo identificadores técnicos originais.
