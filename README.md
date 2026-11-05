# TP9 — Pipeline as Code avec Jenkins

Jenkinsfile, agents Docker, exécution parallèle, JUnit, credentials, image tagguée avec le Git SHA et Multibranch Pipeline.

Projet utilisé : l'API `contact-api` du TP8 (Express, Zod, Helmet, Vitest). Le README du TP8 est conservé dans [README-TP8.md](README-TP8.md).

- Jenkins : `http://192.168.190.141:8080` (VM de lab)
- Image Docker Hub : [`hablani/contact-api`](https://hub.docker.com/r/hablani/contact-api/tags)
- Pipeline : [`Jenkinsfile`](Jenkinsfile)

## Pipeline

```
Checkout → Install → Quality ( Lint ∥ Unit tests ) → Build → Push (main uniquement) → post
```

| Stage | Agent | Rôle |
|---|---|---|
| Checkout | nœud Jenkins | checkout SCM, calcul de `SHORT_SHA = GIT_COMMIT.take(7)` |
| Install | `node:24-alpine` (`reuseNode true`) | `npm ci` |
| Lint | `node:24-alpine` | `npm run lint` (ESLint flat config) |
| Unit tests | `node:24-alpine` | Vitest + rapport JUnit `reports/junit.xml` |
| Build | nœud Jenkins | `docker build` → `hablani/contact-api:<sha>` + label `org.opencontainers.image.revision` |
| Push | nœud Jenkins | `docker login` / `docker push`, **uniquement sur `main`** |

Options : `timestamps()`, `disableConcurrentBuilds()`, `buildDiscarder` (10 builds), `timeout` 20 min.

Blocs `post` : `junit` (always, dans Unit tests), `docker logout` (always, dans Push), message `success` / `failure`, suppression de l'image locale, `cleanWs()` (cleanup).

Les tests d'intégration (PostgreSQL) ne sont pas lancés dans le pipeline : `npm test` exclut `tests/integration/**`.

## Partie 1 — Premier pipeline depuis le dépôt

- `Jenkinsfile` à la racine du dépôt.
- Job **Pipeline** → *Pipeline script from SCM* → Git → ce dépôt → branche `main` → Script Path `Jenkinsfile`.
- Lint ajouté : `npm i -D eslint @eslint/js globals` + `npm pkg set scripts.lint="eslint ."` + [`eslint.config.mjs`](eslint.config.mjs).

![Stages du pipeline](captures/pipeline-stages.png)

## Partie 2 — Agents Docker, parallélisme et rapports

- `Install`, `Lint` et `Unit tests` s'exécutent dans `node:24-alpine` avec `reuseNode true` (même workspace).
- `Lint` et `Unit tests` sont dans un bloc `parallel`.
- Rapport JUnit :
  ```
  npm test -- --reporter=default --reporter=junit --outputFile.junit=reports/junit.xml
  ```
  publié par `junit` dans `post { always }`.
- `npm_config_cache = '.npm-cache'` : le conteneur tourne avec l'UID de Jenkins (pas root), le cache npm est donc placé dans le workspace.
- Test en échec volontaire (`tests/echec-tp9.test.js`) : Unit tests rouge, **Build et Push sautés**, bloc `failure` exécuté, test visible dans l'onglet *Tests*. Le test est ensuite supprimé et le build redevient vert.

![Rapport JUnit](captures/junit-report.png)

## Partie 3 — Image tagguée avec le Git SHA, credentials et push

- Credential Jenkins `dockerhub` (*Username with password*) : utilisateur `hablani` + **access token** Docker Hub (Read & Write), pas le mot de passe.
- Tag de l'image : `hablani/contact-api:<SHORT_SHA>` avec le label `org.opencontainers.image.revision=<GIT_COMMIT>`.
- Push uniquement sur `main` :
  ```groovy
  when { expression { env.BRANCH_NAME == 'main' || env.GIT_BRANCH == 'origin/main' } }
  ```
  (`BRANCH_NAME` en Multibranch, `GIT_BRANCH` dans un job Pipeline simple).
- Commandes `sh` entre **guillemets simples** : c'est le shell qui remplace `$DH_TOKEN`, Groovy n'interpole jamais le secret ; Jenkins l'affiche `****` dans la console.
- `image.txt` (référence complète de l'image) archivé avec `archiveArtifacts`.
- Premier build : image `hablani/contact-api:3427f9c`, identique à `git rev-parse --short HEAD`.

![Token masqué](captures/credentials-masked.png)

![Tag SHA sur Docker Hub](captures/dockerhub-sha-tag.png)

## Partie 4 — Multibranch Pipeline

- Credential GitHub : identifiant + fine-grained personal access token en lecture seule sur le dépôt.
- Job **Multibranch Pipeline** → source GitHub → ce dépôt → *Periodically if not otherwise run* : **2 minutes** (la VM n'est pas joignable depuis Internet, donc pas de webhook).
- Branche `feature/rate-limit-config` + Pull Request → jobs `feature/rate-limit-config` et `PR-1` créés automatiquement.
- Stage **Push sauté** sur la branche et la PR, **exécuté sur `main`** après le merge.

![Multibranch](captures/multibranch.png)

## Défi — Shared Library

- `vars/buildAndPush.groovy` dans un dépôt séparé `jenkins-ci-lib`, déclaré dans *Manage Jenkins → System → Global Pipeline Libraries* sous le nom `ci-lib` (version `main`).
- Chargée dans le Jenkinsfile par `@Library('ci-lib') _`, puis :
  ```groovy
  buildAndPush(image: env.IMAGE_NAME, tag: env.SHORT_SHA, push: env.BRANCH_NAME == 'main')
  ```

![Shared Library](captures/shared-library.png)

## Fichiers ajoutés pour le TP9

| Fichier | Rôle |
|---|---|
| `Jenkinsfile` | pipeline déclaratif final |
| `Dockerfile` | build multi-stage, utilisateur `node`, port 4000 |
| `.dockerignore` | exclut tests, `.env`, `node_modules`, captures… |
| `eslint.config.mjs` | configuration ESLint (ESM, globals Node) |
| `captures/` | captures d'écran des livrables |

## Adaptations à l'environnement

- Jenkins et Docker sur la même VM : `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins`.
- Interface Jenkins en français : *Administrer Jenkins → Credentials → System → Global credentials*.
- Scan périodique du Multibranch à la place du webhook GitHub.
