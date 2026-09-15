#!/bin/sh
# verifica.sh — control de calitate inainte de push.
# Ruleaza din radacina repo-ului corpus:  sh scripts/verifica.sh
#
# Verifica: meta SEO, reciprocitatea hreflang, echilibrul tag-urilor HTML,
# concordanta sitemap-fisiere, cifra de cuvinte declarata, reziduuri necuratate.
#
# Portabil POSIX — functioneaza pe OpenBSD (BSD awk/sed), nu doar pe GNU.

BASE_URL="https://norgedan.github.io/corpus"
probleme=0

ok()      { echo "  OK       $1"; }
problema() { echo "  PROBLEMA $1"; probleme=$((probleme + 1)); }
atentie() { echo "  ATENTIE  $1"; }

echo ""
echo "════════════════════════════════════════════════════"
echo "  Verificare repo corpus"
echo "════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────
echo ""
echo "[1] Meta SEO in documente"

for f in [0-9][0-9]-*.html; do
  [ -f "$f" ] || continue
  lipsa=""
  grep -q 'name="description"'  "$f" || lipsa="$lipsa description"
  grep -q 'rel="canonical"'     "$f" || lipsa="$lipsa canonical"
  grep -q 'hreflang="ro"'       "$f" || lipsa="$lipsa hreflang-ro"
  grep -q 'hreflang="nb"'       "$f" || lipsa="$lipsa hreflang-nb"
  grep -q 'hreflang="x-default"' "$f" || lipsa="$lipsa x-default"
  grep -q 'og:title'            "$f" || lipsa="$lipsa og:title"

  if [ -n "$lipsa" ]; then
    problema "$f lipseste:$lipsa"
  else
    ok "$f"
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[2] Canonical corect (trebuie sa arate spre propriul fisier)"

for f in [0-9][0-9]-*.html; do
  [ -f "$f" ] || continue
  canon=$(grep 'rel="canonical"' "$f" | sed 's|.*href="||; s|".*||')
  if [ "$canon" = "$BASE_URL/$f" ]; then
    ok "$f"
  else
    problema "$f are canonical gresit: $canon"
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[3] Reciprocitate hreflang RO <-> NO"

for ro in [0-9][0-9]-*-ro.html; do
  [ -f "$ro" ] || continue
  # fisierul NO la care arata documentul RO
  no_tinta=$(grep 'hreflang="nb"' "$ro" | sed "s|.*$BASE_URL/||; s|\".*||")

  if [ ! -f "$no_tinta" ]; then
    problema "$ro arata spre $no_tinta — fisierul nu exista"
    continue
  fi

  # fisierul RO la care arata inapoi documentul NO
  ro_intors=$(grep 'hreflang="ro"' "$no_tinta" | sed "s|.*$BASE_URL/||; s|\".*||")

  if [ "$ro_intors" = "$ro" ]; then
    ok "$ro <-> $no_tinta"
  else
    problema "$ro -> $no_tinta, dar $no_tinta -> $ro_intors (nereciproc)"
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[4] Echilibrul tag-urilor HTML"

for f in *.html; do
  [ -f "$f" ] || continue
  dezechilibru=""
  for tag in html head body section; do
    desc=$(grep -o "<$tag[ >]" "$f" | wc -l | tr -d ' ')
    inch=$(grep -o "</$tag>" "$f" | wc -l | tr -d ' ')
    [ "$desc" = "$inch" ] || dezechilibru="$dezechilibru $tag($desc/$inch)"
  done
  # div separat: poate aparea ca <div> sau <div class=...>
  ddesc=$(grep -o '<div' "$f" | wc -l | tr -d ' ')
  dinch=$(grep -o '</div>' "$f" | wc -l | tr -d ' ')
  [ "$ddesc" = "$dinch" ] || dezechilibru="$dezechilibru div($ddesc/$dinch)"

  if [ -n "$dezechilibru" ]; then
    problema "$f dezechilibrat:$dezechilibru"
  else
    ok "$f"
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[5] Sitemap vs. fisiere reale"

if [ -f sitemap.xml ]; then
  # fiecare URL din sitemap are fisier pe disc?
  grep -o "$BASE_URL/[^<]*" sitemap.xml | sed "s|$BASE_URL/||" | while read -r u; do
    [ -z "$u" ] && continue   # URL-ul radacina
    if [ -f "$u" ]; then
      ok "in sitemap si pe disc: $u"
    else
      echo "  PROBLEMA in sitemap dar lipseste pe disc: $u"
    fi
  done

  # fiecare document de pe disc e in sitemap?
  for f in [0-9][0-9]-*.html; do
    [ -f "$f" ] || continue
    if grep -q "$f" sitemap.xml; then
      :
    else
      problema "$f exista pe disc dar NU e in sitemap"
    fi
  done
else
  atentie "sitemap.xml nu exista"
fi

# ─────────────────────────────────────────────────────
echo ""
echo "[6] Numarul de cuvinte: real vs. declarat"

real=$(cat [0-9][0-9]-*.html 2>/dev/null \
       | sed -e '/<style>/,/<\/style>/d' -e 's/<[^>]*>//g' \
       | wc -w | tr -d ' ')

echo "  Cuvinte reale (fara CSS si tag-uri): $real"

for f in index.html README.md; do
  [ -f "$f" ] || continue
  declarat=$(grep -o '~[0-9][0-9.]* de cuvinte\|~[0-9][0-9.]* cuvinte' "$f" | head -1)
  if [ -z "$declarat" ]; then
    atentie "$f nu declara un numar de cuvinte"
    continue
  fi
  # extrage doar cifrele
  cifre=$(echo "$declarat" | tr -cd '0-9')
  # toleranta: +/- 10%
  jos=$((real * 90 / 100))
  sus=$((real * 110 / 100))
  if [ "$cifre" -ge "$jos" ] && [ "$cifre" -le "$sus" ]; then
    ok "$f declara $declarat — corespunde"
  else
    problema "$f declara $declarat, dar realitatea e $real"
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[7] Numarul de documente declarat"

nr_ro=$(ls [0-9][0-9]-*-ro.html 2>/dev/null | wc -l | tr -d ' ')
nr_no=$(ls [0-9][0-9]-*-no.html 2>/dev/null | wc -l | tr -d ' ')
total=$((nr_ro + nr_no))
echo "  Pe disc: $nr_ro RO + $nr_no NO = $total documente"

if [ "$nr_ro" != "$nr_no" ]; then
  problema "numar inegal RO/NO — o versiune lipseste"
else
  ok "perechile RO/NO sunt complete"
fi

if [ -f index.html ]; then
  if grep -q "$total documente" index.html; then
    ok "index.html declara $total documente"
  else
    atentie "index.html nu declara explicit '$total documente' — verifica manual"
  fi
fi

# ─────────────────────────────────────────────────────
echo ""
echo "[8] Reziduuri necuratate"

gasit=""
for pat in "*.bak" "*.tmp" "*.orig" "*~"; do
  for r in $pat; do
    [ -f "$r" ] && gasit="$gasit $r"
  done
done

if [ -n "$gasit" ]; then
  problema "fisiere de sters:$gasit"
else
  ok "niciun reziduu"
fi

# scripturi ramase in radacina
for s in *.sh; do
  [ -f "$s" ] && atentie "script in radacina: $s (ignorat de git, dar sterge-l dupa folosire)"
done

# ─────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
if [ "$probleme" -eq 0 ]; then
  echo "  REZULTAT: totul in regula. Poti face push."
else
  echo "  REZULTAT: $probleme probleme gasite. Repara inainte de push."
fi
echo "════════════════════════════════════════════════════"
echo ""

exit 0
