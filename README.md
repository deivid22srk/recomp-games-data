# Recomp Games Data

Fonte de dados estática (CMS) do app **Recomp Hub** (repositorio `recomp-games-hub`).
O aplicativo consome este repositório via `raw.githubusercontent.com` e o mantém em cache local (Room) para funcionar offline.

## Como funciona

Cada jogo vive em uma pasta dentro de `games/`:

```
games/
└── nome-do-jogo/
    ├── metadata.json      → todos os metadados do jogo
    ├── cover.png          → capa 3:4 (600x800 recomendado)
    ├── banner.png         → banner/hero 16:9 (1600x900 recomendado)
    └── screenshots/
        ├── 1.png          → capturas 16:9 (1280x720 recomendado)
        ├── 2.png
        └── ...
```

O arquivo `index.json` na raiz consolida um resumo de todos os jogos e é o que o aplicativo
carrega primeiro para montar a Home rapidamente.

## Adicionando um jogo novo

1. Crie a pasta `games/<slug>/` (o slug é o identificador usado pelo app).
2. Copie `cover.png`, `banner.png` e as screenshots para a pasta.
3. Crie o `metadata.json` com o schema abaixo.
4. Atualize o `index.json`, adicionando a entrada correspondente (ou rode o script de geração).
5. Abra um PR. O app busca o catálogo pela branch `main`.

## Schema do `metadata.json`

| Campo              | Tipo                | Obrigatório | Descrição |
|--------------------|---------------------|-------------|-----------|
| `slug`             | string              | ✅           | Identificador único (mesmo nome da pasta). |
| `name`             | string              | ✅           | Nome de exibição do jogo. |
| `description`      | string              | ✅           | Descrição que aparece na tela de detalhes. |
| `originalPlatform` | string              | ❌           | Plataforma original (ex.: "Xbox 360 / PS3"). |
| `author`           | string              | ❌           | Autor/times do recomp. |
| `sourceRepo`       | string (url)        | ❌           | Repositório do projeto de recompilação. |
| `status`           | `"released"` / `"beta"` / `"alpha"` / `"in-development"` | ✅ | Status exibido no catálogo. |
| `version`          | string              | ❌           | Versão mais recente disponível. |
| `downloadUrl`      | string (url)        | ❌           | **Link direto do APK (https).** Se ausente/`null`, o app mostra "Sem link de download". |
| `fileSizeBytes`    | number              | ❌           | Tamanho do APK em bytes (para progresso/ETA). |
| `sha256`           | string \| null      | ❌           | Hash de verificação opcional. |
| `tags`             | string[]            | ❌           | Tags exibidas na tela de detalhes. |
| `lastUpdated`      | string (`YYYY-MM-DD`) | ❌        | Data da última atualização. |
| `banner`           | string              | ✅           | Caminho relativo ao `banner.png`. |
| `cover`            | string              | ✅           | Caminho relativo ao `cover.png`. |
| `screenshots`      | string[]            | ❌           | Lista de caminhos relativos das capturas. |

> **Importante:** o app resolve as URLs de imagem como
> `https://raw.githubusercontent.com/deivid22srk/recomp-games-data/<branch>/games/<slug>/<path>`.
> Os caminhos de `banner`, `cover` e `screenshots` devem ser relativos à pasta do jogo.

## Exemplo mínimo

```json
{
  "slug": "meu-jogo",
  "name": "Meu Jogo Recomp",
  "description": "O maior recomp de todos os tempos.",
  "originalPlatform": "GameCube",
  "author": "Equipe X",
  "sourceRepo": "https://github.com/exemplo/recomp",
  "status": "beta",
  "version": "0.9.0",
  "downloadUrl": "https://example.com/meu-jogo.apk",
  "fileSizeBytes": 250000000,
  "sha256": null,
  "tags": ["Ação", "Aventura"],
  "lastUpdated": "2026-08-01",
  "banner": "banner.png",
  "cover": "cover.png",
  "screenshots": ["screenshots/1.png"]
}
```

## Script de geração

As imagens placeholder da pasta `games/` são geradas pelo script
`gen_catalog_data.py` (Python + Pillow), que também regenera `metadata.json` e `index.json`.