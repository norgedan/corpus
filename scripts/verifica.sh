#!/bin/sh
# verifica.sh — control de calitate inainte de push.  Versiunea 2.
#
# Ruleaza din radacina repo-ului:  sh scripts/verifica.sh
# Cod de iesire: 0 = curat, 1 = probleme gasite.
#   Poti inlantui in siguranta:  sh scripts/verifica.sh && git push origin main
#
# Portabil POSIX — merge identic pe OpenBSD (BSD awk/sed/grep) si pe GNU.
# Fara \n in sed, fara \| in grep, fara sed -i, fara conducte care pierd contorul.

BASE_URL="https://norgedan.github.io/corpus"

# Contorul NU se tine intr-o variabila: conductele creeaza subshell-uri
# si incrementarea s-ar pierde.  Fiecare problema se scrie intr-un fisier,
# iar la final se numara liniile.  Asa nimic nu se pierde, oriunde ar aparea.
PROB=$(mktemp /tmp/verifica.XXXXXX) || exit 1
TMP=$(mktemp /tmp/verifica.XXXXXX) || exit 1
trap 'rm -f "$PROB" "$TMP"' EXIT INT TERM
: > "$PROB"

ok()       { echo "  OK       $1"; }
problema() { echo "  PROBLEMA $1"; echo "x" >> "$PROB"; }
atentie()  { echo "  ATENTIE  $1"; }

echo ""
echo "════════════════════════════════════════════════════"
echo "  Verificare repo corpus  ·  v2"
echo "════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────
echo ""
echo "[1] Meta SEO in documente"

for f in [0-9][0-9]-*.html; do
  [ -f "$f" ] || continue
  lipsa=""
  grep -q 'name="description"'   "$f" || lipsa="$lipsa description"
  grep -q 'rel="canonical"'      "$f" || lipsa="$lipsa canonical"
  grep -q 'hreflang="ro"'        "$f" || lipsa="$lipsa hreflang-ro"
  grep -q 'hreflang="nb"'        "$f" || lipsa="$lipsa hreflang-nb"
  grep -q 'hreflang="x-default"' "$f" || lipsa="$lipsa x-default"
  grep -q 'og:title'             "$f" || lipsa="$lipsa og:title"

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
  no_tinta=$(grep 'hreflang="nb"' "$ro" | sed "s|.*$BASE_URL/||; s|\".*||")

  if [ ! -f "$no_tinta" ]; then
    problema "$ro arata spre $no_tinta — fisierul nu exista"
    continue
  fi

  ro_intors=$(grep 'hreflang="ro"' "$no_tinta" | sed "s|.*$BASE_URL/||; s|\".*||")

  if [ "$ro_intors" = "$ro" ]; then
    ok "$ro <-> $no_tinta"
  else
    problema "$ro -> $no_tinta, dar $no_tinta -> $ro_intors (nereciproc)"
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[4] Coerenta lang <-> hreflang"
# Un fisier NO trebuie sa declare lang="nb", unul RO lang="ro".
# Nepotrivirea dintre atributul paginii si hreflang deruteaza motoarele.

for f in [0-9][0-9]-*.html; do
  [ -f "$f" ] || continue
  lang=$(grep -o '<html lang="[a-zA-Z-]*"' "$f" | sed 's|.*lang="||; s|"||')
  case "$f" in
    *-ro.html) asteptat="ro" ;;
    *-no.html) asteptat="nb" ;;
    *)         continue ;;
  esac
  if [ "$lang" = "$asteptat" ]; then
    ok "$f  lang=\"$lang\""
  else
    problema "$f are lang=\"$lang\", se astepta \"$asteptat\""
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[5] Echilibrul tag-urilor HTML"

for f in *.html; do
  [ -f "$f" ] || continue
  dezechilibru=""
  for tag in html head body section blockquote; do
    desc=$(grep -o "<$tag[ >]" "$f" | wc -l | tr -d ' ')
    inch=$(grep -o "</$tag>" "$f" | wc -l | tr -d ' ')
    [ "$desc" = "$inch" ] || dezechilibru="$dezechilibru $tag($desc/$inch)"
  done
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
echo "[6] Artefacte de la sed BSD"
# BSD sed scrie \n ca litera n.  Bug real, intalnit in status-proiect.html:
#   <meta ...>n<meta ...>   in loc de linie noua.

gasit_artefact=0
for f in *.html; do
  [ -f "$f" ] || continue
  if grep -q '">n<' "$f"; then
    problema "$f contine artefact '\">n<' — newline pierdut de sed BSD"
    gasit_artefact=1
  fi
  if grep -q '\\n<' "$f"; then
    problema "$f contine '\\n' literal in text"
    gasit_artefact=1
  fi
done
[ "$gasit_artefact" = "0" ] && ok "niciun artefact"

# ─────────────────────────────────────────────────────
echo ""
echo "[7] Descrieri meta duplicate"
# Doua documente cu aceeasi descriere = continut duplicat pentru Google.
# Se intampla cand copiezi blocul meta de la documentul precedent.

: > "$TMP"
for f in [0-9][0-9]-*.html; do
  [ -f "$f" ] || continue
  d=$(grep 'name="description"' "$f" | sed 's|.*content="||; s|".*||' | cut -c1-60)
  [ -n "$d" ] && echo "$d" >> "$TMP"
done

dup=$(sort "$TMP" | uniq -d | head -3)
if [ -n "$dup" ]; then
  problema "descrieri identice in mai multe documente:"
  echo "$dup" | sed 's|^|             |'
else
  ok "toate descrierile sunt distincte"
fi

# ─────────────────────────────────────────────────────
echo ""
echo "[8] Sitemap vs. fisiere reale"

if [ -f sitemap.xml ]; then
  # URL-urile din sitemap intr-un fisier, ca sa evitam conducta spre while
  grep -o "$BASE_URL/[^<]*" sitemap.xml | sed "s|$BASE_URL/||" | sort -u > "$TMP"

  while read -r u; do
    [ -z "$u" ] && continue
    if [ -f "$u" ]; then
      ok "in sitemap si pe disc: $u"
    else
      problema "in sitemap dar lipseste pe disc: $u"
    fi
  done < "$TMP"

  for f in [0-9][0-9]-*.html; do
    [ -f "$f" ] || continue
    grep -q "$f" sitemap.xml || problema "$f exista pe disc dar NU e in sitemap"
  done
else
  atentie "sitemap.xml nu exista"
fi

# ─────────────────────────────────────────────────────
echo ""
echo "[9] Documente linkuite din index.html"
# O pagina care exista dar nu e linkuita nicaieri e invizibila cititorului.

if [ -f index.html ]; then
  orfane=0
  for f in [0-9][0-9]-*.html; do
    [ -f "$f" ] || continue
    if grep -q "$f" index.html; then
      :
    else
      problema "$f nu e linkuit din index.html (pagina orfana)"
      orfane=1
    fi
  done
  [ "$orfane" = "0" ] && ok "toate documentele sunt linkuite"
else
  atentie "index.html nu exista"
fi

# ─────────────────────────────────────────────────────
echo ""
echo "[10] Numarul de cuvinte: real vs. declarat"
# Numaratoarea se face cu awk, nu cu intervale sed: intervalele
# /<style>/,/<\/style>/ se comporta DIFERIT pe BSD fata de GNU
# (diferenta masurata: ~2000 de cuvinte pe acelasi corpus).

real=$(cat [0-9][0-9]-*.html 2>/dev/null \
       | awk '/<style>/{s=1} /<\/style>/{s=0;next} !s' \
       | sed 's/<[^>]*>//g' \
       | wc -w | tr -d ' ')

echo "  Cuvinte reale (fara CSS si tag-uri): $real"

for f in index.html README.md status-proiect.html; do
  [ -f "$f" ] || continue
  declarat=$(grep -oE '~[0-9][0-9.]* (de )?cuvinte' "$f" | head -1)
  if [ -z "$declarat" ]; then
    atentie "$f nu declara un numar de cuvinte"
    continue
  fi
  cifre=$(echo "$declarat" | tr -cd '0-9')
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
echo "[11] Numarul de documente declarat"

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
echo "[12] Curatenie si stare git"

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

for s in *.sh; do
  [ -f "$s" ] && atentie "script in radacina: $s (ignorat de git, dar sterge-l dupa folosire)"
done

# fisiere netrecute prin git, altele decat modificarile asteptate
if [ -d .git ]; then
  netrecute=$(git status --porcelain 2>/dev/null | grep '^??' | wc -l | tr -d ' ')
  if [ "$netrecute" -gt 0 ]; then
    atentie "$netrecute fisier(e) necunoscut(e) lui git — verifica cu: git status --short"
  else
    ok "git nu vede fisiere straine"
  fi
fi

# ─────────────────────────────────────────────────────
probleme=$(wc -l < "$PROB" | tr -d ' ')

echo ""
echo "════════════════════════════════════════════════════"
if [ "$probleme" -eq 0 ]; then
  echo "  REZULTAT: totul in regula. Poti face push."
  echo "════════════════════════════════════════════════════"
  echo ""
  exit 0
else
  echo "  REZULTAT: $probleme probleme gasite. NU face push."
  echo "════════════════════════════════════════════════════"
  echo ""
  exit 1
fi
