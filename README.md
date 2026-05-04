# Constellation

Package joueur pour rejoindre le serveur Minecraft Forge modde.

## Pour le joueur

1. Telecharger le ZIP Constellation depuis le site.
2. Extraire le ZIP dans un dossier.
3. Double-cliquer sur `Jouer.bat`.

Le launcher installe Prism Launcher si besoin, remplace l'instance fournie, met les mods a jour depuis le manifest GitHub, puis lance le jeu.

Le serveur a rejoindre dans la liste Minecraft est :

```text
82.165.57.177:25566
```

## Preparer le ZIP joueur

La structure finale a zipper doit etre :

```text
Constellation/
+-- Jouer.bat
+-- instance/
|   +-- 1.20.1.zip
+-- updater/
    +-- config.json
    +-- update.ps1
```

Avant de zipper :

1. Exporter l'instance Prism configuree en Minecraft `1.20.1` avec Forge `47.4.10`.
2. Placer l'export ici :

```text
instance/1.20.1.zip
```

3. Verifier `updater/config.json`.
4. Zipper le dossier `CustomUniverse`.
5. Mettre ce ZIP sur le site.

Par defaut, `replaceExistingInstance` vaut `true` dans `updater/config.json`. Le launcher remplace donc l'instance Prism existante par celle du ZIP a chaque lancement avant d'appliquer le manifest.

## Manifest

Le systeme de manifest existant est conserve. Le launcher lit :

```text
https://raw.githubusercontent.com/Jouf17/minecraft-modpack/main/manifest.json
```

Pour publier une mise a jour de mod :

1. Compiler le nouveau `.jar`.
2. Placer le `.jar` dans `mods/`.
3. Modifier `manifest.json` avec le nouveau nom, la nouvelle URL raw GitHub et le hash `sha256`.
4. Commit puis push sur `main`.

Change le nom du `.jar` a chaque version, par exemple `customships-1.0.1.jar`, pour que les anciennes versions soient remplacees proprement.
