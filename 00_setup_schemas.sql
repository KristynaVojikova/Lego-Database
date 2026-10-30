-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 00 – Setup schémat
-- MAGIC Vytvoří schémata pro medallion vrstvy. Idempotentní – může běžet v každém spuštění jobu.
-- MAGIC
-- MAGIC | Schéma | Obsah |
-- MAGIC |---|---|
-- MAGIC | `lego_bronze` | surová data z API, beze změn (jen metadata o načtení) |
-- MAGIC | `lego_silver` | vyčištěná, otypovaná, deduplikovaná a spojená data |
-- MAGIC | `lego_gold` | tabulky připravené pro dashboard |

-- COMMAND ----------

USE CATALOG workspace;

CREATE SCHEMA IF NOT EXISTS lego_bronze COMMENT 'Surová data z Rebrickable a Brickset API';
CREATE SCHEMA IF NOT EXISTS lego_silver COMMENT 'Vyčištěná a spojená data o LEGO setech';
CREATE SCHEMA IF NOT EXISTS lego_gold   COMMENT 'Agregace pro dashboard';