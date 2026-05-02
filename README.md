# Minecraft Modpack

Petit launcher/updater maison pour rejoindre le serveur Minecraft Forge modde.

## Prerequis joueur

1. Installer Prism Launcher :
   <https://prismlauncher.org/>
2. Dans Prism Launcher, importer ou creer une instance nommee exactement `1.20.1`.
3. Configurer cette instance en Minecraft `1.20.1` avec Forge `47.4.10`.
4. Telecharger ce repo GitHub en ZIP, puis l'extraire dans un dossier.
5. Double-cliquer sur `Jouer.bat`.

Le script verifie les mods listes dans `manifest.json`, telecharge uniquement ceux qui manquent, les place dans le dossier mods de l'instance Prism, puis lance Prism Launcher sur le serveur :

```text
82.165.57.177
```

## Fonctionnement

Le script PowerShell lit le manifest distant ici :

```text
https://raw.githubusercontent.com/Jouf17/minecraft-modpack/main/manifest.json
```

Il installe les mods dans :

```text
%APPDATA%\PrismLauncher\instances\1.20.1\.minecraft\mods
```

Avant de telecharger les nouveaux fichiers, il supprime uniquement les anciennes versions des mods maison correspondant a ces patterns :

```text
customships*.jar
customuniverse*.jar
```

Les autres mods presents dans le dossier ne sont pas supprimes.

La detection de mise a jour se fait avec le nom du fichier dans `manifest.json`.
Par exemple, si le manifest passe de `customships-1.0.0.jar` a `customships-1.0.1.jar`, le script supprime l'ancien `customships-1.0.0.jar` et telecharge `customships-1.0.1.jar`.

## Mise a jour des mods cote admin

1. Compiler le nouveau `.jar` du mod.
2. Creer une nouvelle GitHub Release dans le repo du mod.
3. Ajouter le fichier `.jar` a la release.
4. Copier l'URL de telechargement du `.jar`.
5. Modifier `manifest.json` dans ce repo avec le nouveau nom de fichier et la nouvelle URL.
6. Commit puis push sur la branche `main`.

Exemple d'entree dans `manifest.json` :

```json
{
  "name": "customships-1.0.0.jar",
  "url": "https://github.com/Jouf17/custom-ship/releases/download/v1.0.0/customships-1.0.0.jar"
}
```

Au prochain lancement de `Jouer.bat`, les joueurs recevront automatiquement la version indiquee dans le manifest.

Important : pour que la detection fonctionne simplement, change le nom du fichier `.jar` a chaque nouvelle version, par exemple `customships-1.0.1.jar`.

## Depannage

Le script cherche Prism Launcher dans plusieurs chemins courants :

```text
C:\Program Files\PrismLauncher\prismlauncher.exe
C:\Program Files (x86)\PrismLauncher\prismlauncher.exe
%USERPROFILE%\PrismLauncher\prismlauncher.exe
%LOCALAPPDATA%\Programs\PrismLauncher\prismlauncher.exe
```

Si Prism Launcher n'est pas trouve, ajoute son chemin dans `$PrismCandidatePaths` dans `update-and-play.ps1`.

Le chemin attendu pour l'instance est :

```text
%APPDATA%\PrismLauncher\instances\1.20.1
```

Le nom de l'instance Prism doit donc etre exactement `1.20.1`.
