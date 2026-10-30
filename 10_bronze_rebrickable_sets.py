# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "6"
# ///
# MAGIC %md
# MAGIC # 10 – Bronze: Rebrickable sets
# MAGIC Stáhne sety pro Star Wars, Ninjago (do roku 2013) a všechna Botanical témata z Rebrickable API.
# MAGIC Data ukládá beze změn (vše jako string) + metadata o tom, z jakého dotazu přišla.
# MAGIC
# MAGIC **Výstup:** `workspace.lego_bronze.rebrickable_sets` (full refresh)

# COMMAND ----------

import time
import requests
from pyspark.sql import functions as F
from pyspark.sql.types import StructType, StructField, StringType

CATALOG = "workspace"
TARGET_TABLE = f"{CATALOG}.lego_bronze.rebrickable_sets"

# Klíč patří do Databricks secrets, ne do kódu (hlavně když to půjde na Git)
API_KEY = dbutils.secrets.get(scope="lego", key="rebrickable_api_key")
HEADERS = {"Authorization": f"key {API_KEY}", "Accept": "application/json"}
BASE_URL = "https://rebrickable.com/api/v3/lego"
SLEEP_S = 1.2  # limit API ~1 požadavek/s

# COMMAND ----------

def get_json(url, params=None, max_retries=5):
    """GET s retry na 429 (rate limit). Při jiné chybě job spadne – je to lepší než tiše uložit neúplná data."""
    for attempt in range(max_retries):
        r = requests.get(url, headers=HEADERS, params=params, timeout=30)
        if r.status_code == 429:
            time.sleep(5 * (attempt + 1))
            continue
        r.raise_for_status()
        time.sleep(SLEEP_S)
        return r.json()
    raise RuntimeError(f"Rate limit i po {max_retries} pokusech: {url}")


def get_all_pages(url, params=None):
    data = get_json(url, params)
    results = list(data.get("results", []))
    while data.get("next"):
        data = get_json(data["next"])
        results.extend(data.get("results", []))
    return results

# COMMAND ----------

# MAGIC %md
# MAGIC ## Konfigurace dotazů
# MAGIC `tema` se ukládá k datům už tady. Silver pak nemusí odhadovat téma podle `theme_id`
# MAGIC (pokud API vrací i podtémata, mají jiné `theme_id` než 158 / 435).

# COMMAND ----------

themes = get_all_pages(f"{BASE_URL}/themes/", {"page_size": 1000})
botanical_ids = [t["id"] for t in themes if "botanical" in t["name"].lower()]
if not botanical_ids:
    raise ValueError("Nenašlo se žádné Botanical téma – zkontroluj názvy témat v API.")
print(f"Botanical theme IDs: {botanical_ids}")

query_configs = [
    {"tema": "Star Wars", "theme_id": 158, "max_year": None},
    {"tema": "Ninjago",   "theme_id": 435, "max_year": 2013},
] + [{"tema": "Botanical Collection", "theme_id": b_id, "max_year": None} for b_id in botanical_ids]

# COMMAND ----------

rows = []
for cfg in query_configs:
    params = {"theme_id": cfg["theme_id"], "page_size": 1000}
    if cfg["max_year"] is not None:
        params["max_year"] = cfg["max_year"]

    sets = get_all_pages(f"{BASE_URL}/sets/", params)
    for s in sets:
        s["query_tema"] = cfg["tema"]
        s["query_theme_id"] = cfg["theme_id"]
    rows.extend(sets)
    print(f"{cfg['tema']} (theme_id {cfg['theme_id']}): {len(sets)} setů")

if not rows:
    raise ValueError("API nevrátilo žádné sety.")

# COMMAND ----------

# Vše jako string, None zůstává NULL (ne text 'None' jako u pandas astype(str))
columns = sorted({k for r in rows for k in r})
schema = StructType([StructField(c, StringType()) for c in columns])
data = [tuple(None if r.get(c) is None else str(r.get(c)) for c in columns) for r in rows]

df = (
    spark.createDataFrame(data, schema)
    .withColumn("_source", F.lit("rebrickable_api_v3"))
    .withColumn("_ingested_at", F.current_timestamp())
)

(df.write.mode("overwrite")
   .option("overwriteSchema", "true")
   .saveAsTable(TARGET_TABLE))

print(f"Uloženo {df.count()} řádků do {TARGET_TABLE}")