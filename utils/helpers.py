import pandas as pd
import re
import streamlit as st
from utils.snowflake import session

# ==============================
# RUN QUERY
# ==============================
def run_query(q: str) -> pd.DataFrame:
    try:
        return session.sql(q).to_pandas()
    except Exception as e:
        st.error(f"Query error: {e}")
        return pd.DataFrame()

# ==============================
# EXEC QUERY
# ==============================
def exec_query(q: str) -> bool:
    try:
        session.sql(q).collect()
        return True
    except Exception as e:
        st.error(f"Execution error: {e}")
        return False

# ==============================
# SAFE STRING
# ==============================
def safe_str(v) -> str:
    if v is None:
        return ""
    return str(v).replace("'", "''")

# ==============================
# FORMAT SCORE
# ==============================
def format_score(x):
    try:
        f = float(x)
        return int(f) if f == int(f) else round(f, 2)
    except:
        return x

# ==============================
# VALID EMAIL
# ==============================
def is_valid_email(email: str) -> bool:
    return bool(re.match(r"[^@]+@[^@]+\.[^@]+", email.strip()))

# ==============================
# COLOR ROWS
# ==============================
def color_rows(row):
    color = "#d4edda" if row["STATUS"] == "PASS" else "#f8d7da"
    return [f"background-color:{color}"] * len(row)
