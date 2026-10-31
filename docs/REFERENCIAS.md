# Referências científicas e documentação oficial

As fontes abaixo fundamentam **o problema de segurança e as boas práticas**. Os artigos não representam uma certificação de cada regra dos modelos `.gitignore` e `.dockerignore`.

## Artigos científicos

1. Meli, M.; McNiece, M. R.; Reaves, B. **How Bad Can It Git? Characterizing Secret Leakage in Public GitHub Repositories.** Network and Distributed System Security Symposium (NDSS), 2019. DOI: https://doi.org/10.14722/ndss.2019.23418
2. Basak, S. K.; Neil, L.; Reaves, B.; Williams, L. **What are the Practices for Secret Management in Software Artifacts?** IEEE Secure Development Conference (SecDev), 2022. DOI: https://doi.org/10.1109/SecDev53368.2022.00026 ; texto integral: https://arxiv.org/abs/2208.11280
3. Dahlmanns, M. et al. **Secrets Revealed in Container Images: An Internet-wide Study on Occurrence and Impact.** ACM Asia Conference on Computer and Communications Security (ASIA CCS), 2023. DOI: https://doi.org/10.1145/3579856.3590329

## Documentação oficial

- Git: `.gitignore` https://git-scm.com/docs/gitignore
- Git: `git check-ignore` https://git-scm.com/docs/git-check-ignore
- Docker: contexto de build e `.dockerignore` https://docs.docker.com/build/concepts/context/
- Docker: Dockerfile e `RUN --mount=type=bind` https://docs.docker.com/reference/dockerfile/
- Docker: segredos no build https://docs.docker.com/build/building/secrets/

## Leitura crítica

Os modelos mitigam **exposições acidentais por configuração**, mas não garantem ausência de segredos embutidos no código, credenciais já versionadas, vulnerabilidades de dependências ou problemas introduzidos em outras etapas do build.
