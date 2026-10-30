-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 20 – Silver: LEGO sets
-- MAGIC Otypuje, deduplikuje a spojí Rebrickable sety s cenami z Brickset.
-- MAGIC
-- MAGIC - téma se bere z `query_tema` (uložené při stahování), ne z `CASE` nad `theme_id`
-- MAGIC - Brickset je deduplikovaný – Botanical se stahuje přes víc konfigurací, bez toho by `LEFT JOIN` zdvojoval řádky
-- MAGIC - `TRY_CAST` místo `CAST`, aby prázdné hodnoty nerozbily běh v ANSI módu
-- MAGIC
-- MAGIC **Vstup:** `lego_bronze.rebrickable_sets`, `lego_bronze.brickset_sets`
-- MAGIC **Výstup:** `lego_silver.lego_sets`

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

CREATE OR REPLACE TABLE lego_silver.lego_sets
COMMENT 'LEGO sety (Star Wars, Ninjago do 2013, Botanical) s původní cenou'
AS
WITH rebrickable AS (
    SELECT *
    FROM lego_bronze.rebrickable_sets
    QUALIFY ROW_NUMBER() OVER (PARTITION BY set_num ORDER BY _ingested_at DESC) = 1
),
brickset AS (
    SELECT
        set_num,
        subtheme,
        TRY_CAST(retail_price_eur AS DECIMAL(10, 2)) AS puvodni_cena_eur,
        TRY_CAST(retail_price_usd AS DECIMAL(10, 2)) AS puvodni_cena_usd,
        TRY_CAST(rating AS DOUBLE)                    AS hodnoceni,
        TRY_CAST(minifigs AS INT)                     AS pocet_minifigurek
    FROM lego_bronze.brickset_sets
    -- při duplicitě preferuj záznam, který má cenu
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY set_num
        ORDER BY (retail_price_eur IS NULL), (retail_price_usd IS NULL)
    ) = 1
)
SELECT
    r.set_num                          AS originalni_cislo,
    split_part(r.set_num, '-', 1)      AS cislo_setu,
    r.name                             AS nazev_stavebnice,
    TRY_CAST(r.year AS INT)            AS rok_vydani,
    r.query_tema                       AS tema,
    b.subtheme                         AS podtema,
    TRY_CAST(r.num_parts AS INT)       AS pocet_dilku,
    b.pocet_minifigurek,
    b.puvodni_cena_eur,
    b.puvodni_cena_usd,
    b.hodnoceni,
    r.set_url,
    r.set_img_url,
    current_timestamp()                AS _updated_at
FROM rebrickable r
LEFT JOIN brickset b
    ON r.set_num = b.set_num;

-- COMMAND ----------

-- Rychlá kontrola kvality: kolik setů má cenu
SELECT
    tema,
    COUNT(*)                                        AS pocet_setu,
    COUNT(puvodni_cena_eur)                         AS s_cenou_eur,
    ROUND(COUNT(puvodni_cena_eur) / COUNT(*) * 100) AS pokryti_cen_pct
FROM lego_silver.lego_sets
GROUP BY tema
ORDER BY tema;
