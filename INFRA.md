# Smart Construction — Infraestrutura (PM-04)

Provisionamento (Terraform), configuração (Ansible) e operação (GitHub Actions) do
Smart Construction na AWS (us-east-2).

```
Internet ──HTTPS 443──▶ VM app (Elastic IP)                    VM db (exclusiva)
                        ├─ gateway Nginx :80/:443               └─ PostgreSQL 17
                        ├─ web (Next.js) :3000                     escuta só no IP privado
                        ├─ api (FastAPI) :8000 ──SQL 5432 (rede privada, SG app→db)──▶
                        ├─ storage (SeaweedFS editorial)        disco EBS /srv/data
                        └─ private-storage (SeaweedFS privado)
                        disco EBS /srv/data
                                         backups ──▶ S3 privado
```

## Workflows

| Workflow | O que faz |
|---|---|
| `build-images` | Após o CI, constrói e publica as imagens no GHCR com tag `sha-xxxxxxx` |
| `deploy` | `apply` / `plan` / `destroy` — Terraform e depois Ansible, com parâmetros |
| `restore-test` | Restaura o último backup num PostgreSQL descartável no runner |

## Parâmetros do `deploy`

| Parâmetro | Efeito |
|---|---|
| `action` | apply (criar/atualizar), plan (só mostrar), destroy (encerrar) |
| `environment` | dev / homolog / prod — state e recursos separados |
| `instance_name` | tag Name da VM da aplicação |
| `app_instance_type` / `db_instance_type` | tamanho das VMs (alteração in-place) |
| `docker_tag` | versão das imagens; recria só os contêineres afetados |
| `update_os` | aplica `apt upgrade` e reinicia se necessário |
| `extra_packages` | pacotes extras instalados pelo Ansible |
| `run_backup` | executa backup imediato para o S3 |

## Segredos

| GitHub Secret | Uso |
|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Terraform e AWS CLI na pipeline |
| `SSH_PUBLIC_KEY` / `SSH_PRIVATE_KEY` | acesso do Ansible às VMs (porta 22 aberta só durante o job) |
| `DUCKDNS_TOKEN` | apontar o domínio para o Elastic IP |
| `SMART_SECRETS_SEED` | gera as 10 credenciais de `.secrets/` do projeto (banco, SeaweedFS) |
| `ADMIN_PASSWORD` | senha do login `admin` criado na primeira execução |

Variáveis (não sensíveis): `TF_STATE_BUCKET`, `DUCKDNS_SUBDOMAIN`, `LETSENCRYPT_EMAIL`.

## Etapas manuais (justificadas)

1. Criar o bucket do Terraform state (o state não pode guardar a si mesmo).
2. Criar usuário IAM / access key e cadastrar os GitHub Secrets.
3. Criar o subdomínio no DuckDNS.
4. Tornar públicos os pacotes do GHCR (uma vez).
