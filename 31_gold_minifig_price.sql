-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 31 – Gold: cena vs. počet figurek
-- MAGIC
-- MAGIC | Tabulka | K čemu |
-- MAGIC |---|---|
-- MAGIC | `lego_gold.sets_minifig_price` | 1 řádek = 1 set; pro scatter plot cena × počet figurek |
-- MAGIC | `lego_gold.price_by_minifig_count` | průměrné ceny podle počtu figurek (0, 1, … 8+) – bar/line graf |
-- MAGIC | `lego_gold.minifig_price_effect` | kolik EUR v průměru přidá 1 figurka navíc, podle tématu – KPI |
-- MAGIC | `lego_gold.sets_overview` | všechny sety se základními údaji + počet figurek + obrázek – hlavní přehled |
-- MAGIC | `lego_gold.minifigs_in_sets` | 1 řádek = figurka v setu, s obrázky figurky i setu – hledání figurek |
-- MAGIC | `lego_gold.minifigs_catalog` | 1 řádek = figurka; v kolika setech je, od kdy – karta figurky |
-- MAGIC
-- MAGIC Pozor: víc figurek obvykle znamená i větší set. Proto je vedle ceny i **cena za dílek**,
-- MAGIC která vliv velikosti setu částečně očistí.
-- MAGIC
-- MAGIC **Vstup:** `lego_gold.sets_dashboard`, `lego_silver.set_minifig_counts`

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

CREATE OR REPLACE TABLE lego_gold.sets_minifig_price AS
SELECT
    d.originalni_cislo,
    d.nazev_stavebnice,
    d.tema,
    d.rok_vydani,
    d.pocet_dilku,
    c.pocet_figurek,
    c.pocet_unikatnich_figurek,
    d.puvodni_cena_eur,
    d.cena_za_dilek_eur,
    ROUND(d.puvodni_cena_eur / NULLIF(c.pocet_figurek, 0), 2) AS cena_za_figurku_eur,
    d.set_img_url
FROM lego_gold.sets_dashboard d
JOIN lego_silver.set_minifig_counts c
    ON c.originalni_cislo = d.originalni_cislo
WHERE c.pocet_figurek IS NOT NULL
  AND d.puvodni_cena_eur IS NOT NULL;

-- COMMAND ----------

CREATE OR REPLACE TABLE lego_gold.price_by_minifig_count AS
SELECT
    tema,
    LEAST(pocet_figurek, 8)                                   AS pocet_figurek_sort,
    CASE WHEN pocet_figurek >= 8 THEN '8+'
         ELSE CAST(pocet_figurek AS STRING) END               AS pocet_figurek_skupina,
    COUNT(*)                                                  AS pocet_setu,
    ROUND(AVG(puvodni_cena_eur), 2)                           AS prumerna_cena_eur,
    ROUND(PERCENTILE(puvodni_cena_eur, 0.5), 2)               AS medianova_cena_eur,
    ROUND(AVG(pocet_dilku))                                   AS prumer_dilku,
    ROUND(AVG(cena_za_dilek_eur), 3)                          AS prumerna_cena_za_dilek_eur
FROM lego_gold.sets_minifig_price
GROUP BY ALL;

-- COMMAND ----------

-- Lineární regrese: o kolik EUR v průměru roste cena s každou figurkou navíc
CREATE OR REPLACE TABLE lego_gold.minifig_price_effect AS
SELECT
    tema,
    COUNT(*)                                                     AS pocet_setu,
    ROUND(REGR_SLOPE(puvodni_cena_eur, pocet_figurek), 2)        AS eur_za_figurku_navic,
    ROUND(REGR_R2(puvodni_cena_eur, pocet_figurek), 2)           AS r2_figurky,
    ROUND(REGR_SLOPE(puvodni_cena_eur, pocet_dilku) * 100, 2)    AS eur_za_100_dilku_navic,
    ROUND(REGR_R2(puvodni_cena_eur, pocet_dilku), 2)             AS r2_dilky
FROM lego_gold.sets_minifig_price
GROUP BY tema;

-- COMMAND ----------

-- Hlavní přehled setů: všechny sety (i bez ceny / bez figurek), LEFT JOIN
CREATE OR REPLACE TABLE lego_gold.sets_overview AS
SELECT
    d.cislo_setu,
    d.originalni_cislo,
    d.nazev_stavebnice,
    d.tema,
    d.podtema,
    d.rok_vydani,
    d.pocet_dilku,
    c.pocet_figurek,
    c.pocet_unikatnich_figurek,
    d.puvodni_cena_eur,
    d.puvodni_cena_usd,
    d.cena_za_dilek_eur,
    d.hodnoceni,
    d.set_img_url,
    d.set_url
FROM lego_gold.sets_dashboard d
LEFT JOIN lego_silver.set_minifig_counts c
    ON c.originalni_cislo = d.originalni_cislo;

-- COMMAND ----------

-- Figurky v setech: filtr na název figurky → obrázek figurky + sety, ve kterých je
CREATE OR REPLACE TABLE lego_gold.minifigs_in_sets AS
SELECT
    f.cislo_figurky,
    f.nazev_figurky,
    f.obrazek_figurky,
    f.pocet_kusu,
    f.dilku_figurky,
    o.cislo_setu,
    o.nazev_stavebnice,
    o.tema,
    o.rok_vydani,
    o.puvodni_cena_eur,
    o.set_img_url
FROM lego_silver.set_minifigs f
JOIN lego_gold.sets_overview o
    ON o.originalni_cislo = f.originalni_cislo;

-- COMMAND ----------

-- Katalog figurek: 1 řádek = 1 figurka
CREATE OR REPLACE TABLE lego_gold.minifigs_catalog AS
SELECT
    cislo_figurky,
    ANY_VALUE(nazev_figurky)                       AS nazev_figurky,
    ANY_VALUE(obrazek_figurky)                     AS obrazek_figurky,
    ANY_VALUE(dilku_figurky)                       AS dilku_figurky,
    ANY_VALUE(tema)                                AS tema,
    COUNT(DISTINCT cislo_setu)                     AS v_kolika_setech,
    MIN(rok_vydani)                                AS prvni_rok,
    MAX(rok_vydani)                                AS posledni_rok,
    ARRAY_JOIN(COLLECT_SET(nazev_stavebnice), ', ') AS sety
FROM lego_gold.minifigs_in_sets
GROUP BY cislo_figurky;
