# Git + Docker Security Baseline

**Modelos reutilizáveis de `.gitignore` e `.dockerignore` para reduzir a exposição acidental de arquivos sensíveis em projetos de software.**

Este repositório apresenta dois modelos comentados, pensados para diferentes linguagens e frameworks. Eles são uma base de segurança para adaptar, não regras universais que possam ser aplicadas sem revisar o projeto.

## 1. Por que dois arquivos?

| Arquivo | Função | Limite importante |
| --- | --- | --- |
| `.gitignore` | Orienta o Git a ignorar arquivos ainda não rastreados. | Não remove arquivos já versionados nem impede `git add -f`. |
| `.dockerignore` | Filtra o contexto enviado ao Docker builder. | Não inspeciona comandos posteriores nem camadas da imagem final. |

Um arquivo ignorado no Git pode continuar presente no contexto Docker; um arquivo excluído do contexto Docker pode continuar versionado no Git. As duas configurações são complementares.

## 2. Modelos principais

- [`.gitignore`](.gitignore) - ambientes locais, credenciais, chaves, configurações pessoais, caches e dumps.
- [`.dockerignore`](.dockerignore) - bloqueios semelhantes aplicados ao contexto de build, sem excluir indiscriminadamente artefatos legítimos.

A baseline **não** ignora por padrão todo `bin/`, `vendor/`, `dist/`, `*.sql`, Markdown ou documentação. Esses elementos podem ser necessários ao build e precisam ser avaliados conforme a stack.

Arquivos de exemplo como `.env.example` são permitidos **apenas quando não contêm segredos reais**. Documentos compartilhados para agentes de IA (como `AGENTS.md` e `CLAUDE.md`) podem ser versionados pelo Git, mas são excluídos do contexto Docker por padrão quando desnecessários ao runtime.

## 3. Como adotar no seu projeto

1. Revise os dois modelos com a equipe e **integre** as regras aos arquivos existentes, em vez de sobrescrevê-los automaticamente.
2. Coloque o `.gitignore` na raiz do repositório e o `.dockerignore` na raiz do **contexto** usado em `docker build`.
3. Revise as exceções `!` no final dos arquivos. Não libere credenciais de produção para fazer o build funcionar.
4. Confirme se o projeto necessita de `vendor`, `dist`, `bin`, migrations SQL, certificados públicos ou documentação durante o build.
5. Garanta que secrets necessários ao processo sejam fornecidos por mecanismos apropriados, como BuildKit secret mounts ou serviços de segredos, não por `COPY` de arquivos locais.

No Git, para investigar uma regra específica:

```bash
git check-ignore -v --no-index .env
```

Se um segredo já foi commitado, deve ser **revogado/rotacionado** e tratado no histórico; adicionar uma linha ao `.gitignore` não resolve a exposição anterior.

## 4. Validador opcional: evitar publicar um contexto indevido

O [`validar-modelos.sh`](validar-modelos.sh) possui dois modos:

**A. Validar as regras (fora do Docker):**

```bash
bash validar-modelos.sh --check-rules
```

Verifica casos de exclusão e preservação com o **motor do Git** e a presença de proteções mínimas **canônicas** no `.dockerignore` (checagem estática). Essa etapa não analisa o contexto real e não reproduz o motor de padrões do Docker.

**B. Validar o contexto real DURANTE `docker build`:**

Consulte [`Dockerfile.exemplo`](Dockerfile.exemplo), que utiliza uma etapa de segurança ANTES de copiar código-fonte. O trecho principal é:

```dockerfile
RUN --mount=type=bind,source=.,target=/context \
    bash /context/validar-modelos.sh \
      --rules-dir /context --context /context \
    && touch /security-approved
```

Esse `RUN` inspeciona o contexto efetivamente recebido pelo builder, depois que o `.dockerignore` foi aplicado. Arquivos de alto risco conhecidos fazem o script retornar erro e **interrompem o build**. Arquivos ambíguos (por exemplo, PEMs que podem conter certificados públicos) geram avisos. O exemplo vincula explicitamente o stage de aplicação ao de validação para evitar que o primeiro pule o segundo.

O comando de demonstração é:

```bash
docker build --no-cache --progress=plain -f Dockerfile.exemplo -t security-baseline-demo .
```

**Importante:** `Dockerfile.exemplo` é um *esqueleto*. Ele não compila uma aplicação real. Substitua o stage final pelo da sua stack. Para denunciar a ausência de arquivos indispensáveis, acrescente `--require-path` na chamada do script, por exemplo `--require-path src/main.js`.

Por que não fazer `COPY . .` e só depois `RUN validar-modelos.sh`? Porque, se algum arquivo indevido for copiado, ele pode permanecer numa camada anterior mesmo que seja excluído depois. O exemplo monta o contexto somente leitura **sem copiá-lo para uma camada**.

## 5. Limites de segurança

- O contexto inspecionado pelo `RUN` já passou pelo `.dockerignore`: o script **não enxerga arquivos que foram excluídos antes**. Não é possível provar sua existência original apenas olhando o contexto filtrado.
- A checagem das regras Docker é estrutural e conserva a sintaxe canônica deste modelo. Equivalências mais complexas ou exceções de um `.dockerignore` específico por Dockerfile exigem revisão separada.
- O validador detecta caminhos de alto risco e algumas assinaturas de segredos conhecidos, mas **não substitui secret scanning**. Arquivos grandes podem ter o conteúdo ignorado pela inspeção de assinaturas, com aviso.
- O exemplo **não inspeciona a imagem final**, camadas históricas, dependências nem segredos introduzidos posteriormente via `RUN`, `ARG`, `ENV` ou fontes externas.
- Um resultado aprovado não garante que a aplicação esteja livre de vulnerabilidades ou credenciais expostas.
- A inspeção do contexto pelo script não verifica se todo arquivo necessário ao aplicativo foi preservado; para isso, use `--require-path` e testes da própria aplicação.

## 6. Fundamentação

A motivação do projeto vem de pesquisas sobre vazamento de credenciais no Git e em imagens de container. As pesquisas fundamentam o problema, **não validam individualmente cada padrão** fornecido. Consulte [referências científicas e documentação oficial](docs/REFERENCIAS.md).

## Licença

[MIT](LICENSE). Modelos fornecidos como base de estudo e adaptação, sem garantia de adequação a todas as tecnologias e ambientes.
