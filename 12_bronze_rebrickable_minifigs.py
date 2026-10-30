# Databricks notebook source
# MAGIC %md
# MAGIC # 12 – Bronze: Rebrickable minifigurky (CSV export)
# MAGIC Místo volání API pro každý set zvlášť (~25 min kvůli rate limitu) stáhne denní CSV export
# MAGIC celé Rebrickable databáze. Jsou to 3 soubory, žádný rate limit, běh v řádu vteřin.
# MAGIC
# MAGIC | Soubor | Obsah |
# MAGIC |---|---|
# MAGIC | `inventories` | inventář setu (set_num → inventory_id, set může mít víc verzí) |
# MAGIC | `inventory_minifigs` | které figurky a kolik kusů jsou v inventáři |
# MAGIC | `minifigs` | katalog figurek (název, počet dílků, obrázek) |
# MAGIC
# MAGIC **Výstup:** `lego_bronze.rb_inventories`, `lego_bronze.rb_inventory_minifigs`, `lego_bronze.rb_minifigs` (full refresh)

# COMMAND ----------

import io
import requests
import pandas as pd
from pyspark.sql import functions as F

CATALOG = "workspace"
BASE_URL = "https://cdn.rebrickable.com/media/downloads"
FILES = {
    "rb_inventories": "inventories.csv.gz",
    "rb_inventory_minifigs": "inventory_minifigs.csv.gz",
    "rb_minifigs": "minifigs.csv.gz",
}

# COMMAND ----------

for table, file_name in FILES.items():
    url = f"{BASE_URL}/{file_name}"
    r = requests.get(url, headers={"User-Agent": "lego-databricks-pipeline"}, timeout=120)
    r.raise_for_status()

    # Vše jako string – typy řeší silver
    pdf = pd.read_csv(io.BytesIO(r.content), compression="gzip", dtype=str, keep_default_na=False)
    pdf = pdf.replace({"": None})

    df = (
        spark.createDataFrame(pdf)
        .withColumn("_source", F.lit(url))
        .withColumn("_ingested_at", F.current_timestamp())
    )

    target = f"{CATALOG}.lego_bronze.{table}"
    (df.write.mode("overwrite")
       .option("overwriteSchema", "true")
       .saveAsTable(target))
    print(f"{target}: {len(pdf)} řádků")
