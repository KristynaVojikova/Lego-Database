# Databricks notebook source
# MAGIC %md
# MAGIC # 11 – Bronze: Brickset sets
# MAGIC Stáhne sety z Brickset API (Star Wars, Ninjago, Botanical napříč tématy).
# MAGIC Ukládá vybraná pole jako string + celý původní záznam v `raw_json`, aby šlo později
# MAGIC vytáhnout další údaje (hodnocení, data dostupnosti, ceny UK/CA…) bez nového stahování.
# MAGIC
# MAGIC **Výstup:** `workspace.lego_bronze.brickset_sets` (full refresh)

# COMMAND ----------

import json
import time
import requests
from pyspark.sql import functions as F
from pyspark.sql.types import StructType, StructField, StringType

CATALOG = "workspace"
TARGET_TABLE = f"{CATALOG}.lego_bronze.brickset_sets"

BRICKSET_API_KEY = dbutils.secrets.get(scope="lego", key="brickset_api_key")
URL = "https://brickset.com/api/v3.asmx/getSets"
PAGE_SIZE = 500

configs = [
    {"theme": "Star Wars"},
    {"theme": "Ninjago"},
    {"theme": "Icons", "subtheme": "Botanical Collection"},
    {"theme": "Creator Expert", "subtheme": "Botanical Collection"},
    {"theme": "Botanicals"},
]

# COMMAND ----------

def fetch_page(cfg, page):
    params = {"pageSize": PAGE_SIZE, "pageNumber": page, **cfg}
    r = requests.get(
        URL,
        params={"apiKey": BRICKSET_API_KEY, "userHash": "", "params": json.dumps(params)},
        timeout=30,
    )
    r.raise_for_status()
    data = r.json()
    if data.get("status") != "success":
        raise RuntimeError(f"Brickset chyba pro {cfg}, strana {page}: {data.get('message')}")
    return data.get("sets", [])

# COMMAND ----------

rows = []
for cfg in configs:
    page, count = 1, 0
    while True:
        sets = fetch_page(cfg, page)
        if not sets:
            break
        for s in sets:
            lego_com = s.get("LEGOCom") or {}
            rows.append({
                "set_num": f"{s.get('number')}-{s.get('numberVariant')}",
                "name": s.get("name"),
                "year": s.get("year"),
                "theme": s.get("theme"),
                "subtheme": s.get("subtheme"),
                "pieces": s.get("pieces"),
                "minifigs": s.get("minifigs"),
                "rating": s.get("rating"),
                "retail_price_eur": (lego_com.get("DE") or {}).get("retailPrice"),
                "retail_price_usd": (lego_com.get("US") or {}).get("retailPrice"),
                "query_config": json.dumps(cfg),
                "raw_json": json.dumps(s),
            })
        count += len(sets)
        if len(sets) < PAGE_SIZE:
            break
        page += 1
        time.sleep(1)
    print(f"{cfg}: {count} setů")

if not rows:
    raise ValueError("Brickset API nevrátilo žádné sety.")

# COMMAND ----------

# Explicitní schéma – jinak Spark spadne, když je nějaký sloupec celý NULL
columns = list(rows[0].keys())
schema = StructType([StructField(c, StringType()) for c in columns])
data = [tuple(None if r[c] is None else str(r[c]) for c in columns) for r in rows]

df = (
    spark.createDataFrame(data, schema)
    .withColumn("_source", F.lit("brickset_api_v3"))
    .withColumn("_ingested_at", F.current_timestamp())
)

(df.write.mode("overwrite")
   .option("overwriteSchema", "true")
   .saveAsTable(TARGET_TABLE))

print(f"Uloženo {df.count()} řádků do {TARGET_TABLE}")
