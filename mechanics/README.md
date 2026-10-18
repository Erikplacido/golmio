# Mecânicas plugáveis

Cada pasta aqui é uma mecânica. O `MechanicRegistry` as descobre sozinho; não existe lista para editar.
Arquitetura completa: [`docs/ARQUITETURA.md`](../../docs/ARQUITETURA.md). Backlog: [`docs/MECANICAS.md`](../../docs/MECANICAS.md).

## Criar uma mecânica nova

1. Copie `_template/` para `<seu_id>/`. O id tem que ser igual ao nome da pasta, em `snake_case`.
2. No `_init()`, preencha `title`, `description`, `layer` e `stage = "experimental"`, e mantenha `enabled_by_default = false`.
3. Coloque **todo número de balanceamento** em `default_params`.
4. Escolha os hooks em [`core/mechanics/hooks.gd`](../core/mechanics/hooks.gd):
   - regras da partida → `setup_match(ctx)` com `ctx.bus.on(...)`;
   - regras de mundo, carreira ou economia → `install(bus)`.
5. Guarde dados em `ext[<seu_id>]` e estado de partida em `ctx.state_for(<seu_id>)`. **Nunca** use variáveis da instância para isso.
6. Para aleatoriedade, use `ctx.rng_for(id)`. Fora da partida (camada `meta`), a semente chega no payload, porque o servidor a gera com `Backend.new_seed()`. Derive fluxos com `SeededRng.new(seed).fork("...")` ou `AthleteDna.derive_seed(seed, "...")`, como fazem `athlete_generator` e `packs`.
7. Ligue em `rulesets/dev.json`: `"<seu_id>": { "enabled": true }`.
8. Crie `tests/unit/test_<seu_id>.gd`. O teste de fumaça já roda a mecânica sozinha e junto com as demais.
9. Rode `./tests/run.sh` e o balanceamento (`tests/balance.gd`).
10. Quando estiver aprovada: `stage = "stable"`, ligue em `default.json` e suba a `version` do ruleset.

## Não pode

- Chamar outra mecânica diretamente. Se precisar de algo dela, peça que ela ofereça um hook (`provides_hooks`) ou use um do núcleo.
- Mexer em `ext` de outra mecânica.
- Usar `randf()`, `randi()`, `Time.*` ou `OS.*` em regras. Isso quebra o determinismo e o servidor.
- Usar `sin`/`cos`/`atan2`/`pow` ou métodos compostos do `Vector2` (`length`, `distance_to`, `normalized`, `dot`, `angle`...). Use `DMath`, senão o jogo diverge entre celular, PC e navegador. O `test_determinism` barra isso automaticamente.
- Colocar números mágicos no código.
- Mudar arquivos em `core/` como "atalho". Se faltar um ponto de extensão, proponha um hook novo (ver ARQUITETURA → "Evoluindo o contrato").

## Mudar uma mecânica existente

- Mudou o **comportamento** → suba `version`. Ela entra na assinatura das partidas.
- Mudou o **formato** dos dados em `ext` → suba `data_version` e implemente `migrate_data(owner_kind, from_version, data)`.
- Mudou só um **número** → altere o ruleset, não o código.

## Cancelar ou remover

1. `"enabled": false` no ruleset. O efeito é imediato e dá para voltar atrás.
2. `stage = "deprecated"`. O registro avisa enquanto ela estiver ligada em algum ruleset.
3. Apague a pasta. Os dados em `ext` ficam dormentes nos saves, e rulesets que ainda a citem geram só um aviso.
4. Atualize o `docs/MECANICAS.md`.
