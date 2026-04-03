# minecraft-docker-server

Serveur Minecraft clé en main avec dashboard web, backups automatiques, tunnel Playit.gg et sauvegarde cloud.

## Fonctionnalités

- **Dashboard web** — Start/Stop, logs en temps réel, console
- **Backup automatique** toutes les heures (7 jours de rétention)
- **Tunnel Playit.gg** — rend le serveur accessible depuis internet sans port forwarding
- **Sauvegarde cloud** — push automatique du monde sur GitHub à chaque arrêt
- **Statut partagé** — détecte si quelqu'un héberge déjà via GitHub Gist
- **Launcher `.exe`** — démarre tout automatiquement (Docker, serveur, tunnel)

---

## Prérequis

Installe ces outils avant de commencer :

| Outil | Lien |
|---|---|
| Docker Desktop | https://www.docker.com/products/docker-desktop |
| Git | https://git-scm.com/download/win |
| Bun | https://bun.sh |
| PowerShell 5+ | Inclus dans Windows 10/11 |

---

## Installation

### 1. Cloner le repo

```bash
git clone https://github.com/ton-pseudo/minecraft-docker-server.git
cd minecraft-docker-server
```

### 2. Configurer `.env`

Copie le fichier exemple et remplis les valeurs :

```bash
copy .env.example .env
```

Ouvre `.env` et remplis chaque valeur (voir section **Configuration** ci-dessous).

### 3. Compiler le launcher

```powershell
# Autoriser les scripts PowerShell (une seule fois)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Installer ps2exe (une seule fois)
Install-Module ps2exe -Scope CurrentUser
Import-Module ps2exe

# Compiler
Invoke-PS2EXE -InputFile .\launcher.ps1 -OutputFile .\launcher.exe -NoConsole
```

### 4. Lancer

Double-cliquer sur `launcher.exe`.

---

## Configuration

### Minecraft

| Variable | Description | Exemple |
|---|---|---|
| `MC_VERSION` | Version du serveur | `1.21.4` |
| `MC_TYPE` | Type de serveur | `VANILLA`, `PAPER`, `FORGE` |
| `RAM` | RAM allouée | `4G`, `8G` |
| `MOTD` | Nom affiché | `Mon Serveur` |
| `GAMEMODE` | Mode de jeu | `survival`, `creative` |
| `DIFFICULTY` | Difficulté | `normal`, `hard` |
| `MAX_PLAYERS` | Joueurs max | `10` |
| `PORT` | Port réseau | `25565` |
| `RCON_PASSWORD` | Mot de passe RCON | Génère un mot de passe aléatoire |

### GitHub (pour la sauvegarde cloud et le statut partagé)

**1. Créer un token GitHub**

Va sur : `github.com → Settings → Developer settings → Personal access tokens → Tokens (classic)`
- Coche les permissions : **repo** + **gist**
- Copie le token dans `GITHUB_TOKEN`

**2. Créer un Gist**

Va sur : `gist.github.com`
- Filename : `mc-status.json`
- Contenu :
```json
{ "running": false, "hostName": "", "since": "" }
```
- Clique "Create secret gist"
- Copie l'ID (les chiffres/lettres à la fin de l'URL) dans `GIST_ID`

**3. URL du repo**

Mets l'URL de ton repo Git dans `GIT_REPO_URL` (ex: `https://github.com/username/mon-serveur.git`)

### Playit.gg (tunnel internet)

**1. Créer un compte** sur `playit.gg`

**2. Télécharger l'agent** et le placer dans le dossier du projet sous le nom `playit.exe`

**3. Lancer l'agent** une première fois et créer un tunnel TCP sur le port 25565

**4. Récupérer la clé secrète** dans `%LOCALAPPDATA%\playit_gg\playit.toml`

**5. Récupérer l'adresse** du tunnel (ex: `monserveur.joinmc.link`)

---

## Utilisation

### Lancer le serveur

Double-cliquer sur `launcher.exe`. Il va automatiquement :
1. Récupérer les dernières mises à jour (`git pull`)
2. Lancer Docker Desktop si nécessaire
3. Démarrer les containers (Minecraft + Dashboard + Backup)
4. Lancer le tunnel Playit.gg
5. Ouvrir le dashboard dans le navigateur

### Dashboard

Accessible sur `http://localhost:3000`

- **Start / Stop** du serveur
- **Logs** en temps réel
- **Console** pour envoyer des commandes Minecraft

### Arrêter le serveur

Utiliser le bouton **Stop** dans le dashboard.  
→ Le monde est sauvegardé et pushé sur GitHub automatiquement.

---

## Partager avec des amis

1. Créer un repo **privé** sur GitHub
2. Pusher le projet (avec le `.env`)
3. Tes amis clonent le repo, installent Docker Desktop + Git, et double-cliquent sur `launcher.exe`

> Le launcher se met à jour automatiquement à chaque lancement via `git pull`.

---

## Mettre à jour le launcher

Si tu modifies `launcher.ps1`, recompile :

```powershell
Invoke-PS2EXE -InputFile .\launcher.ps1 -OutputFile .\launcher.exe -NoConsole
git add .
git commit -m "Mise à jour launcher"
git push
```
