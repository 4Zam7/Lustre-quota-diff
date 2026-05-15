# lustre-project-quota-diff

Scripts d'analyse des différences de quotas projet Lustre entre deux exports `glb-prj`.

Disponibles en trois unités selon vos préférences d'affichage :

| Script | Unité |
|--------|-------|
| `lustre-project-quota-diff_ko.sh` | Kilo-octets (Ko) |
| `lustre-project-quota-diff_mo.sh` | Méga-octets (Mo) |
| `lustre-project-quota-diff_go.sh` | Giga-octets (Go) |

Utiles notamment après un `lctl set_param osd-ldiskfs.*.quota_slave.force_reint=1` pour
comprendre ce qui a changé dans les compteurs de quota et identifier les projets impactés.

---

## Contexte

Sur un filesystem Lustre, les quotas projet sont gérés par le **QMT** (Quota Master Target),
qui agrège les remontées de chaque **quota slave** (un par OST/MDT).

Ces compteurs peuvent se désynchroniser avec la réalité disque après :
- un crash ou redémarrage d'OSS
- un failover
- des suppressions de fichiers effectuées pendant qu'un OSS était indisponible

La commande `force_reint=1` force chaque OSD à recompter l'usage réel depuis le disque
et à le remonter au QMT :

```bash
clush -bw @mds,@oss 'lctl set_param osd-ldiskfs.*.quota_slave.force_reint=1'
```

Pour capturer l'état avant/après et analyser les différences, ces scripts comparent deux exports
du QMT au format `glb-prj` (global project quota).

---

## Générer les fichiers d'export

> ⚠️ Ces commandes sont à exécuter **depuis le serveur QMT** (généralement le MDS primaire).

**Avant** le `force_reint` :
```bash
lctl get_param qmt.*.dt-0x0.glb-prj > glb-prj-before.txt
```

**Après** le `force_reint` (attendre quelques secondes que la réintégration soit terminée) :
```bash
lctl get_param qmt.*.dt-0x0.glb-prj > glb-prj-after.txt
```

---

## Utilisation

```bash
# Rendre les scripts exécutables (une seule fois)
chmod +x lustre-project-quota-diff_ko.sh
chmod +x lustre-project-quota-diff_mo.sh
chmod +x lustre-project-quota-diff_go.sh

# Lancer avec l'unité souhaitée
./lustre-project-quota-diff_ko.sh glb-prj-before.txt glb-prj-after.txt
./lustre-project-quota-diff_mo.sh glb-prj-before.txt glb-prj-after.txt
./lustre-project-quota-diff_go.sh glb-prj-before.txt glb-prj-after.txt
```

---

## Exemple de sortie (version Mo)

```
STATUT                 ID       HARD(Mo)  AVANT(Mo)  APRES(Mo)  %AVANT  %APRES    DELTA(Mo)
-------------------------------------------------------------------------------------
NOUVEAU_DEPASSEMENT    42           2048        890       2340   43.5%  114.3%       +1450 <<<
RESOLU                 17           1024       1025        612  100.1%   59.8%        -413
TOUJOURS_DEPASSE       305          1024       1980       1980  193.4%  193.4%          +0 <<<
sous-estime            88           5120       1200       2900   23.4%   56.6%       +1700
sur-estime             201         10240       9100       6200   88.9%   60.5%       -2900 <<<
sur-estime             74            250        230        198   92.0%   79.2%         -32 <<<
```

---

## Explication des colonnes

| Colonne | Description |
|---------|-------------|
| `STATUT` | Résultat de la comparaison (voir tableau ci-dessous) |
| `ID` | Identifiant du projet Lustre |
| `HARD(Ko/Mo/Go)` | Limite maximale configurée pour ce projet |
| `AVANT(Ko/Mo/Go)` | Espace comptabilisé par le QMT **avant** la réintégration |
| `APRES(Ko/Mo/Go)` | Espace comptabilisé par le QMT **après** la réintégration |
| `%AVANT` | Taux d'utilisation avant |
| `%APRES` | Taux d'utilisation après |
| `DELTA(Ko/Mo/Go)` | Correction appliquée (positif = le QMT sous-estimait, négatif = il surestimait) |

Le marqueur **`<<<`** signale les projets dont l'usage dépasse 90% du hard limit après réintégration.

---

## Explication des statuts

| Statut | Signification | Action recommandée |
|--------|---------------|-------------------|
| `RESOLU` | Le projet semblait dépasser son quota mais ce n'était qu'un artefact de comptage. Le compteur a été corrigé à la baisse. | ✅ Rien à faire, les alertes vont disparaître. |
| `NOUVEAU_DEPASSEMENT` | Le projet ne semblait pas en dépassement mais l'était vraiment. Le QMT sous-estimait l'usage réel. | 🔴 À traiter : contacter l'utilisateur ou augmenter la limite. |
| `TOUJOURS_DEPASSE` | Le projet dépasse son quota avant ET après. Le `force_reint` n'a rien changé : c'est un vrai dépassement connu. Un `delta=0` confirme que les compteurs étaient déjà corrects. | 🔴 Dépassement réel à traiter. |
| `sous-estime` | Le QMT sous-estimait l'usage (delta positif) mais sans dépasser le hard limit. | ⚠️ À surveiller si le projet est proche de sa limite. |
| `sur-estime` | Le QMT surestimait l'usage (delta négatif). Des fichiers avaient été supprimés sans que les slaves remontent la libération. | ✅ Normal après un crash/failover, espace libéré récupéré. |

---

## Filtrer les résultats

Par défaut les scripts affichent les projets avec un delta > 5% du hard limit, ou impliqués dans un dépassement.

Pour n'afficher que les dépassements actifs :
```bash
./lustre-project-quota-diff_mo.sh before.txt after.txt | grep -E "DEPASSE|NOUVEAU"
```

Pour identifier un projet spécifique :
```bash
./lustre-project-quota-diff_mo.sh before.txt after.txt | grep "^TOUJOURS_DEPASSE"
```

Pour trouver à quel utilisateur/chemin correspond un ID de projet :
```bash
lfs project -l /mnt/lustre | grep "^<id>"
lfs quota -p <id> /mnt/lustre
```

---

## Prérequis

- `bash` >= 4
- `awk` (compatible BSD awk et gawk)
- `diff`
- Accès aux fichiers d'export `glb-prj` du QMT

---

## Auteur

Généré dans le cadre d'une investigation sur la désynchronisation des quotas Lustre après `force_reint`.
