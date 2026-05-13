#!/bin/bash
# lustre-project-quota-diff_ko.sh
# Analyse les différences de quotas projet Lustre entre deux exports glb-prj
# Usage : ./lustre-quota-diff.sh <avant> <apres>
# Exemple : ./lustre-quota-diff.sh glb-prj-before.txt glb-prj-after.txt

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage : $0 <fichier_avant> <fichier_apres>"
    exit 1
fi

BEFORE="$1"
AFTER="$2"

if [ ! -f "$BEFORE" ]; then
    echo "Erreur : fichier introuvable : $BEFORE"
    exit 1
fi

if [ ! -f "$AFTER" ]; then
    echo "Erreur : fichier introuvable : $AFTER"
    exit 1
fi

diff -u "$BEFORE" "$AFTER" | awk '
# Capture du project ID depuis les lignes de contexte (espace devant dans diff -u)
/^ - id:/  { id=$NF }
/^- - id:/ { id=$NF }

# Lecture des valeurs AVANT (lignes supprimées, préfixe -)
/^-[^-].*limits:/ {
    split($0, t, "granted:"); split(t[2], g, ","); before=g[1]+0;
    split($0, t, "hard:");    split(t[2], h, ","); hard=h[1]+0;
}

# Lecture des valeurs APRÈS (lignes ajoutées, préfixe +)
/^\+[^\+].*limits:/ {
    split($0, t, "granted:"); split(t[2], g, ","); after=g[1]+0;
    delta = after - before;

    if (hard > 0) {
        abs_delta = delta < 0 ? -delta : delta;
        pct_delta        = abs_delta / hard * 100;
        pct_used_before  = before / hard * 100;
        pct_used_after   = after  / hard * 100;

        # Filtre : changement > 5% du hard OU dépassement de quota
        if (pct_delta > 5 || before > hard || after > hard) {
            hard_ko   = hard   / 1024;
            before_ko = before / 1024;
            after_ko  = after  / 1024;
            delta_ko  = delta  / 1024;

            if      (before > hard && after <= hard) statut = "RESOLU";
            else if (before <= hard && after > hard) statut = "NOUVEAU_DEPASSEMENT";
            else if (before > hard && after > hard)  statut = "TOUJOURS_DEPASSE";
            else if (delta > 0)                      statut = "sous-estime";
            else                                     statut = "sur-estime";

            printf "%s|%s|%.0f|%.0f|%.0f|%.1f|%.1f|%+.0f|%.1f\n",
                statut, id, hard_ko, before_ko, after_ko,
                pct_used_before, pct_used_after, delta_ko, pct_delta;
        }
    }
}
' | sort -t'|' -k9 -rn | awk -F'|' '
BEGIN {
    printf "\n%-22s %-8s %10s %10s %10s %7s %7s %12s\n",
        "STATUT", "ID", "HARD(Ko)", "AVANT(Ko)", "APRES(Ko)", "%AVANT", "%APRES", "DELTA(Ko)";
    printf "%s\n", "-------------------------------------------------------------------------------------";
}
{
    alert = ($7+0 > 90) ? " <<<" : "";
    printf "%-22s %-8s %10s %10s %10s %6s%% %6s%%%12s%s\n",
        $1, $2, $3, $4, $5, $6, $7, $8, alert;
}
'
