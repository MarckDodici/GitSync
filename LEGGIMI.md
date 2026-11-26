# Patch per il fork MarckDodici/GitSync

Base: commit `91b6af2` (quello indicizzato da Graphify). 8 file toccati, nessun file di workflow.

## Cosa cambia
1. **Login GitHub senza segreti** – nuovo `lib/api/manager/auth/github_device_flow.dart` (OAuth Device Flow, RFC 8628)
   e override di `launchOAuthFlow` in `github_manager.dart`. Usa il Client ID pubblico della tua OAuth App
   (`Ov23liDaf9PrbQ7Qckir`, impostato in `lib/constant/secrets.dart.template`, che il workflow esistente copia in `secrets.dart`).
   Gestisce authorization_pending, slow_down, expired_token, access_denied. Scope: read:user, user:email, repo, workflow, read:org.
   I token delle OAuth App non scadono, quindi non c'e' refresh token.
2. **Premium sempre attivo** – `premium_manager.dart` riscritto: nessuna verifica sponsor, nessuna chiamata di rete,
   `cullNonPremium` non rimuove piu' repository. `riverpod_providers.dart`: il premium non puo' tornare a `false`
   (prima succedeva dopo "cancella dati"). `onboarding_setup.dart`: non mostra piu' la schermata di sblocco.
3. `global.dart` / `main.dart`: `rootNavigatorKey` per mostrare la finestra con il codice del Device Flow.

Nel tuo fork `_readPremiumStatus()` restituiva gia' `true` (l'upstream legge lo stato sponsor): il grosso era gia' fatto,
questa patch elimina i residui (controllo di rete, cull dei repo, schermata onboarding, reset dopo "cancella dati").

## Come applicarla
- **Con GitHub Folder Uploader**: decomprimi lo zip sul telefono, scegli la cartella `gitsync-patch`, repository
  `MarckDodici/GitSync`, branch `main`. Il file `PATCH.diff` e questo `LEGGIMI.md` puoi escluderli (o lasciarli: sono innocui).
- **Con git**: `git apply PATCH.diff` dalla radice del fork (il diff usa i prefissi `orig/` e `patched/`: `git apply -p1`).

Poi: scheda *Actions* > *Build Debug APK* > *Run workflow*. L'APK e' nell'artifact `gitsync-apk`.

## Requisiti sulla OAuth App
Device Flow attivo (gia' fatto). Per i repository di organizzazioni con restrizioni OAuth serve l'approvazione dell'admin.

## Limiti dichiarati
- **Non compilato qui** (niente Flutter/Dart nell'ambiente): se la build segnala errori, incolla il log.
- GitLab, Gitea e Codeberg restano con il vecchio flusso e Client ID vuoti: per loro serve una tua applicazione
  registrata su quel server. HTTPS con token e SSH funzionano come prima.
- L'opzione "GitHub App / scoped" richiede una tua GitHub App (`gitHubAppClientId` e' vuoto): se scelta, mostra un messaggio.
- Testi del dialog Device Flow solo in inglese.
- Licenza GPL-3.0: se distribuisci l'APK, il sorgente modificato deve restare disponibile con la stessa licenza.
