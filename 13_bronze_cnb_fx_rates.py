# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "6"
# ///
# MAGIC %md
# MAGIC # 13 – Bronze: kurzy ČNB
# MAGIC Stáhne denní kurzy devizového trhu ČNB za každý rok od roku 1999 (vznik eura) do současnosti.
# MAGIC Formát souboru: `Datum|1 AUD|1 EUR|...|1 USD|...`, desetinná čárka. Hlavička se může
# MAGIC v průběhu roku opakovat, když ČNB změní seznam měn – parser na to reaguje.
# MAGIC
# MAGIC **Výstup:** `workspace.lego_bronze.cnb_fx_rates` (long formát: 1 řádek = datum × měna, full refresh)

# COMMAND ----------

import time
import datetime
import requests
from pyspark.sql import functions as F
from pyspark.sql.types import StructType, StructField, StringType

CATALOG = "workspace"
TARGET_TABLE = f"{CATALOG}.lego_bronze.cnb_fx_rates"
URL = "https://www.cnb.cz/cs/financni-trhy/devizovy-trh/kurzy-devizoveho-trhu/kurzy-devizoveho-trhu/rok.txt"
FIRST_YEAR = 1999
LAST_YEAR = datetime.date.today().year

# COMMAND ----------

def parse_year(text, year):
    """Vrátí seznam (datum, mena, mnozstvi, kurz, rok_souboru) jako stringy."""
    rows, header = [], None
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("|")
        if parts[0] == "Datum":
            # sloupce typu "1 EUR" / "100 JPY" → (mnozstvi, mena)
            header = [tuple(col.split(" ", 1)) for col in parts[1:]]
            continue
        if header is None:
            continue
        for (mnozstvi, mena), kurz in zip(header, parts[1:]):
            if kurz:
                rows.append((parts[0], mena, mnozstvi, kurz, str(year)))
    return rows

# COMMAND ----------

all_rows = []
for year in range(FIRST_YEAR, LAST_YEAR + 1):
    r = requests.get(URL, params={"rok": year}, timeout=60)
    r.raise_for_status()
    rows = parse_year(r.text, year)
    if not rows:
        raise ValueError(f"ČNB nevrátila žádné kurzy pro rok {year}")
    all_rows.extend(rows)
    print(f"{year}: {len(rows)} záznamů")
    time.sleep(0.3)

# COMMAND ----------

schema = StructType([
    StructField("datum", StringType()),
    StructField("mena", StringType()),
    StructField("mnozstvi", StringType()),
    StructField("kurz", StringType()),
    StructField("rok_souboru", StringType()),
])

df = (
    spark.createDataFrame(all_rows, schema)
    .withColumn("_source", F.lit("cnb_rok_txt"))
    .withColumn("_ingested_at", F.current_timestamp())
)

(df.write.mode("overwrite")
   .option("overwriteSchema", "true")
   .saveAsTable(TARGET_TABLE))

print(f"Uloženo {df.count()} řádků do {TARGET_TABLE}")