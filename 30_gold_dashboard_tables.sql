-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 30 – Gold: tabulky pro dashboard
-- MAGIC
-- MAGIC | Tabulka | K čemu |
-- MAGIC |---|---|
-- MAGIC | `lego_gold.sets_dashboard` | detail setů + odvozené metriky (cena za dílek, dekáda) – tabulky, filtry, obrázky |
-- MAGIC | `lego_gold.theme_year_stats` | vývoj v čase podle tématu – line/bar grafy |
-- MAGIC | `lego_gold.theme_summary` | souhrn za téma – KPI karty |
-- MAGIC
-- MAGIC **Vstup:** `lego_silver.lego_sets`

-- COMMAND ----------

USE CATALOG workspace;

-- COMMAND ----------

CREATE OR REPLACE TABLE lego_gold.sets_dashboard AS
SELECT
    *,
    ROUND(puvodni_cena_eur / NULLIF(pocet_dilku, 0), 3) AS cena_za_dilek_eur,
    ROUND(puvodni_cena_usd / NULLIF(pocet_dilku, 0), 3) AS cena_za_dilek_usd,
    FLOOR(rok_vydani / 10) * 10                         AS dekada,
    puvodni_cena_eur IS NOT NULL                        AS ma_cenu
FROM lego_silver.lego_sets
WHERE pocet_dilku > 0;  -- vyřadí položky bez dílků (gear, prázdné záznamy)

-- COMMAND ----------

CREATE OR REPLACE TABLE lego_gold.theme_year_stats AS
SELECT
    tema,
    rok_vydani,
    COUNT(*)                          AS pocet_setu,
    SUM(pocet_dilku)                  AS dilku_celkem,
    ROUND(AVG(pocet_dilku))           AS prumer_dilku,
    ROUND(AVG(puvodni_cena_eur), 2)   AS prumerna_cena_eur,
    -- vážený průměr: jen sety, které mají cenu
    ROUND(SUM(puvodni_cena_eur) / NULLIF(SUM(CASE WHEN ma_cenu THEN pocet_dilku END), 0), 3)
                                      AS cena_za_dilek_eur
FROM lego_gold.sets_dashboard
GROUP BY tema, rok_vydani;

-- COMMAND ----------

CREATE OR REPLACE TABLE lego_gold.theme_summary AS
SELECT
    tema,
    COUNT(*)                                    AS pocet_setu,
    MIN(rok_vydani)                             AS prvni_rok,
    MAX(rok_vydani)                             AS posledni_rok,
    SUM(pocet_dilku)                            AS dilku_celkem,
    ROUND(AVG(pocet_dilku))                     AS prumer_dilku,
    ROUND(AVG(puvodni_cena_eur), 2)             AS prumerna_cena_eur,
    ROUND(AVG(cena_za_dilek_eur), 3)            AS prumerna_cena_za_dilek_eur,
    MAX_BY(nazev_stavebnice, pocet_dilku)       AS nejvetsi_set,
    MAX(pocet_dilku)                            AS nejvetsi_set_dilku,
    MAX_BY(nazev_stavebnice, puvodni_cena_eur)  AS nejdrazsi_set,
    MAX(puvodni_cena_eur)                       AS nejdrazsi_set_eur
FROM lego_gold.sets_dashboard
GROUP BY tema;
