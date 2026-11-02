# «Tilgang» gir en claude mcp add-kommando uten --scope user

- loop: mcp-add-scope
- mode: hands-on
- stage: ship
- base: 43b7afb67987d976b79cc0a655c0488a710686f8
- after: database-wait
- item: sak_basvzt1hqb8g5yab
- verified: 8a3bbbc66e2005014241588c5b0ee0bed8c0f6af
- shown: 8a3bbbc66e2005014241588c5b0ee0bed8c0f6af

## Brief

Ferdig sak_basvzt1hqb8g5yab, filed 2026-11-01 after Jonas pasted the
command nixploy-dashboard's «Access» gave him and no Claude session outside
~/nixos saw the server: «Kommandoen Tun viser på «Access»/«Tilgang» når et
token lages (src/web/access.lisp, linje 380 og 448) er claude mcp add
--transport http NAVN URL --header "Authorization: Bearer tun_…" uten
--scope. Claude Code legger da serveren i «local»-omfanget, bare for mappen
kommandoen kjøres i.» Wanted: «Ta med --scope user, så serveren gjelder i
alle mapper på maskinen. Si under kommandoen at den skal kjøres i en egen
terminal, ikke med ! i en Claude-økt, så tokenet ikke havner i samtalen.
Gjelder alle Tun-klienter …; eksemplet i src/web/ui/data.lisp linje 1167
likeså.» On 2026-11-02 Jonas asked to «fix the items in ferdig that regard
tun».

## Criteria

1. The command `/access` shows under «Connect without a token» is
   `claude mcp add --scope user --transport http NAME URL`.
2. The command shown with a new token is the same with `--header
   "Authorization: Bearer TOKEN"`. No advice under it: at gate B Jonas
   said «You do not need to mention in the UI to run it in a separate
   terminal».
3. The specimen's code-block example, the client template's README and
   docs/client-api.md give the command with `--scope user`.
4. Tests: the OAuth and token pages' commands carry `--scope user`.

## Decisions

- **`--scope user`, not `project`:** a project scope writes `.mcp.json`
  into the folder, which would put the token in a repository.
- **No advice in the UI** about where to run the token's command (Jonas at
  gate B); the template README keeps one line on it for developers.
- **spec/auth.md §6** names the command and the warning, since the page is
  Tun's own and every client shows it.

## Log

- 2026-11-02 07:52  started, hands-on
- 2026-11-02 07:54  gate A asked of the person
- 2026-11-02 07:56  gate A: approve (jonas): «Approve (Recommended)»
- 2026-11-02 08:12  verify 1: passed build, test, check
- 2026-11-02 08:26  verify 2: passed build, test, check
- 2026-11-02 08:27  shown (/access)
- 2026-11-02 08:27  gate B asked of the person
- 2026-11-02 09:43  gate B: changes (jonas): «Changes» → «Different wording» → «As a warning box»: «Run this in your own terminal, not in Claude Code, so the token stays out of the conversation.» as a warning alert like «Copy it now»
- 2026-11-02 09:59  verify 3: passed build, test, check
- 2026-11-02 09:59  shown (/access, /ui/code-block)
- 2026-11-02 09:59  gate B asked of the person
- 2026-11-02 09:59  gate B: approve (jonas): «Approve and push (Recommended)»; under the token's command «Nothing (Recommended)», after «You do not need to mention in the UI to run it in a separate terminal»
