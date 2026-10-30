-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 31 – Gold: cena vs. počet figurek
-- MAGIC
-- MAGIC | Tabulka | K čemu |
-- MAGIC |---|---|
-- MAGIC | `lego_gold.sets_minifig_price` | 1 řádek = 1 set; pro scatter plot cena × počet figurek |
-- MAGIC | `lego_gold.price_by_minifig_count` | průměrné ceny podle počtu figurek (0, 1, … 8+) – bar/line graf |
-- MAGIC | `lego_gold.minifig_price_effect` | kolik EUR v průměru přidá 1 figurka navíc, podle tématu – KPI |
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
