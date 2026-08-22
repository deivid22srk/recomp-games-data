# Backups do banco de dados (Supabase)

Backups SQL do projeto Supabase **hailgames** (projeto `tsriuhkellkwwaqficid`),
que é o banco usado pelo app **Recomp Hub**.

| Arquivo | Data | Conteúdo |
|---------|------|----------|
| `backup_hailgames_2026-08-22.sql` | 22/08/2026 | Schema `public` completo + dados + funções + políticas + storage |

## O que está incluído

- Tabelas `public`: `games`, `game_screenshots`, `profiles`, `categories`, `content_items`, `app_releases`
- Dados de todas as tabelas públicas
- Funções: `is_admin`, `is_owner`, `is_principal_admin`, `promote_to_admin`, `handle_new_user`, `sync_profile_username`, `set_updated_at`
- Políticas de Row Level Security
- Índices e grants
- Bucket de storage `content` (público) com suas políticas

## Privacidade

Por segurança, **este backup NÃO contém**:

- Dados da schema `auth` (usuários, e-mails, hashes de senha, sessões, refresh tokens)
- E-mails reais dos usuários — o campo `email` de `profiles` foi anonimizado como `user@redacted.invalid`

O e-mail do ADM principal aparece hardcoded nas funções `is_principal_admin()`,
`promote_to_admin()` e na política `profiles_update`. Ele foi substituído pelo
placeholder `PRINCIPAL_ADMIN_EMAIL`. Ao restaurar em outro projeto, defina o
e-mail real do ADM principal:

```bash
sed -i 's/PRINCIPAL_ADMIN_EMAIL/seu-email@exemplo.com/g' backup.sql
```

## Como restaurar

1. No painel do Supabase (Studio → SQL Editor), cole o conteúdo do arquivo `.sql` e execute.
2. Recrie os usuários de autenticação pelo GoTrue (Sign up), pois a schema `auth` não está no backup.
3. Após o primeiro login, o trigger `handle_new_user` recria os perfis automaticamente.
